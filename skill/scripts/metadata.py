"""Local metadata operations. ExifTool is an external runtime dependency."""

import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import gpx


class PhotoError(ValueError):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def run(arguments):
    executable = shutil.which('exiftool')
    if not executable:
        raise PhotoError('missing_dependency', 'ExifTool is not on PATH')
    result = subprocess.run([executable, '-config', '', *arguments],
                            capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise PhotoError('exiftool_error', result.stderr.strip() or 'ExifTool failed')
    return result.stdout


def read(path):
    values = json.loads(run(['-j', '-n', '-G1', '-FileType',
        '-EXIF:DateTimeOriginal', '-EXIF:OffsetTimeOriginal', '-EXIF:SubSecTimeOriginal',
        '-EXIF:CreateDate', '-EXIF:ModifyDate', '-GPS:all', '-XMP-exif:GPS*',
        '-Composite:GPSLatitude', '-Composite:GPSLongitude', '-Composite:GPSAltitude', str(path)]))[0]
    if 'Error' in values or 'ExifTool:Error' in values:
        raise PhotoError('read_failed', values.get('Error', values.get('ExifTool:Error')))
    return values


def parse_zone(value):
    if value is None:
        return None
    if value in ('UTC', 'Z'):
        return timezone.utc
    if re.fullmatch(r'[+-]\d{2}:\d{2}', value):
        hours, minutes = map(int, value[1:].split(':'))
        if hours > 23 or minutes > 59:
            raise ValueError('Invalid UTC offset')
        return timezone(timedelta(minutes=(hours * 60 + minutes) * (1 if value[0] == '+' else -1)))
    try:
        return ZoneInfo(value)
    except ZoneInfoNotFoundError as error:
        raise ValueError('Unknown timezone or missing system timezone database: ' + value) from error


def capture_time(values, zone=None):
    raw = values.get('ExifIFD:DateTimeOriginal')
    if not raw:
        raise PhotoError('missing_time', 'EXIF DateTimeOriginal is missing')
    try:
        stamp = datetime.strptime(raw, '%Y:%m:%d %H:%M:%S')
        sub = str(values.get('ExifIFD:SubSecTimeOriginal', ''))
        if sub:
            if not sub.isdigit():
                raise ValueError('Invalid subsecond value')
            stamp = stamp.replace(microsecond=int((sub + '000000')[:6]))
        offset = values.get('ExifIFD:OffsetTimeOriginal')
        effective = parse_zone(offset) if offset else zone
        if effective is None:
            raise PhotoError('missing_timezone', 'Supply --timezone for a photo without an EXIF offset')
        a, b = stamp.replace(tzinfo=effective, fold=0), stamp.replace(tzinfo=effective, fold=1)
        if a.utcoffset() != b.utcoffset():
            raise PhotoError('ambiguous_time', 'DST transition requires an explicit UTC offset')
        if a.astimezone(timezone.utc).astimezone(effective).replace(tzinfo=None) != stamp:
            raise PhotoError('invalid_time', 'Nonexistent local time')
        return a.timestamp()
    except PhotoError:
        raise
    except (ValueError, KeyError, OverflowError) as error:
        raise PhotoError('invalid_time', str(error)) from error


def has_gps(values):
    return any(key in values for key in ('GPS:GPSLatitude', 'GPS:GPSLongitude',
                                         'Composite:GPSLatitude', 'Composite:GPSLongitude'))


def check_xmp(values):
    if any(key.startswith('XMP-exif:GPS') for key in values):
        raise PhotoError('unsupported_xmp_gps', 'Embedded XMP GPS requires reconciliation; not supported')


def position(values, assume_wgs84=False):
    check_xmp(values)
    try:
        lat, lon = float(values['Composite:GPSLatitude']), float(values['Composite:GPSLongitude'])
        if not gpx.coordinate(lat, lon):
            raise ValueError('Coordinates out of range')
    except (KeyError, TypeError, ValueError) as error:
        raise PhotoError('missing_coordinates', 'No valid signed GPS coordinates') from error
    datum = values.get('GPS:GPSMapDatum')
    if datum:
        if str(datum).upper().replace('-', '').replace(' ', '') != 'WGS84':
            raise PhotoError('unsupported_datum', 'GPSMapDatum is not WGS84')
    elif not assume_wgs84:
        raise PhotoError('unknown_datum', 'Missing GPSMapDatum; --assume-wgs84 requires user intent')
    elevation = values.get('Composite:GPSAltitude')
    try:
        elevation = float(elevation) if elevation is not None else None
        if elevation is not None and not math.isfinite(elevation):
            elevation = None
    except (ValueError, TypeError):
        elevation = None
    return dict(lat=lat, lon=lon, elevation=elevation)


def digest(path):
    with Path(path).open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def write_copy(source, target, match, original, original_hash):
    created = False
    try:
        # Exclusive creation avoids replacing any pre-existing destination.
        with target.open('xb') as destination:
            created = True
            with source.open('rb') as incoming:
                shutil.copyfileobj(incoming, destination)
        if digest(target) != original_hash:
            raise PhotoError('source_changed', 'Source changed after metadata inspection')
        os.chmod(target, 0o600)
        args = ['-overwrite_original', '-GPS:all=',
                f"-GPSLatitude={abs(match['lat']):.10f}",
                '-GPSLatitudeRef=' + ('S' if match['lat'] < 0 else 'N'),
                f"-GPSLongitude={abs(match['lon']):.10f}",
                '-GPSLongitudeRef=' + ('W' if match['lon'] < 0 else 'E'),
                '-GPSMapDatum=WGS-84', '-GPSProcessingMethod=GPX']
        if match.get('elevation') is not None:
            args += [f"-GPSAltitude={abs(match['elevation']):.6f}",
                     '-GPSAltitudeRef#=' + ('1' if match['elevation'] < 0 else '0')]
        run([*args, str(target)])
        saved = read(target)
        actual = position(saved)
        if abs(actual['lat'] - match['lat']) > 1e-6 or abs(actual['lon'] - match['lon']) > 1e-6:
            raise PhotoError('verification_failed', 'GPS coordinate readback differs')
        expected_elevation = match.get('elevation')
        if ((expected_elevation is None and actual['elevation'] is not None)
                or (expected_elevation is not None and (actual['elevation'] is None
                    or abs(expected_elevation - actual['elevation']) > 0.01))):
            raise PhotoError('verification_failed', 'GPS altitude readback differs')
        for key in ('ExifIFD:DateTimeOriginal', 'ExifIFD:OffsetTimeOriginal',
                    'ExifIFD:SubSecTimeOriginal', 'ExifIFD:CreateDate', 'IFD0:ModifyDate'):
            if original.get(key) != saved.get(key):
                raise PhotoError('verification_failed', 'Photo timestamp changed')
        if digest(source) != original_hash:
            raise PhotoError('source_changed', 'Source changed during export')
    except BaseException:
        if created:
            target.unlink(missing_ok=True)
        raise
