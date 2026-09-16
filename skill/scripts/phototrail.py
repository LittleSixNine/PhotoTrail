#!/usr/bin/env python3
"""Two standalone PhotoTrail workflows. Python 3.11+; ExifTool on PATH."""

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import platform
import sys
import subprocess
import xml.etree.ElementTree as ET

if sys.version_info < (3, 11):
    print(json.dumps({'status': 'error', 'code': 'missing_dependency',
                      'reason': 'Python 3.11 or newer is required'}))
    sys.exit(2)

import gpx
import metadata

VERSION = '0.1.0'
PHOTO_EXTENSIONS = {'.jpg', '.jpeg', '.heic', '.heif', '.png', '.tif', '.tiff',
                    '.dng', '.cr2', '.cr3', '.nef', '.arw', '.raf', '.orf', '.rw2', '.xmp'}


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError(message)


def emit(value):
    print(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False))


def positive(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError('Must be a positive finite number')
    return number


def finite(value):
    number = float(value)
    if not math.isfinite(number):
        raise argparse.ArgumentTypeError('Must be finite')
    return number


def regular_path(value):
    path = Path(value).expanduser().absolute()
    if any(part.is_symlink() for part in (path, *path.parents)):
        raise ValueError(f'Symbolic links are not supported: {path}')
    return path.resolve()


def photos(inputs):
    found = []
    for value in inputs:
        path = regular_path(value)
        if path.is_dir():
            candidates = sorted(item for item in path.iterdir()
                                if not item.name.startswith('.') and item.suffix.lower() in PHOTO_EXTENSIONS)
        else:
            candidates = [path]
        for candidate in candidates:
            candidate = regular_path(candidate)
            if not candidate.is_file():
                raise ValueError(f'Input is not a regular file: {candidate}')
            if candidate not in found:
                found.append(candidate)
    if not found:
        raise ValueError('No photo files found; directory inputs are not recursive')
    return found


def report(command, args):
    return dict(version=VERSION, schema_version=1, command=command,
                settings={key: value for key, value in vars(args).items() if key != 'command'},
                results=[])


def finish(result):
    result['counts'] = dict(Counter(item['status'] for item in result['results']))
    result['status'] = 'partial' if any(item['status'] in ('skipped', 'failed')
                                       for item in result['results']) else 'ok'
    return 3 if result['status'] == 'partial' else 0


def failure(item, error):
    item.update(status='skipped' if isinstance(error, metadata.PhotoError)
                and error.code not in ('read_failed', 'exiftool_error', 'verification_failed', 'source_changed')
                else 'failed', code=getattr(error, 'code', 'file_error'), reason=str(error))


def export_gpx(args):
    sources = photos(args.photos)
    output = regular_path(args.output)
    if output.exists() or not output.parent.is_dir():
        raise ValueError('GPX output must be a new file in an existing directory')
    zone = metadata.parse_zone(args.timezone)
    result, points = report(args.command, args), []
    for source in sources:
        item = dict(source=str(source))
        try:
            values = metadata.read(source)
            point = metadata.position(values, args.assume_wgs84)
            point.update(time=metadata.capture_time(values, zone), name=source.name)
            points.append(point)
            item.update(status='exported', code='exported')
        except (ValueError, OSError, subprocess.SubprocessError) as error:
            failure(item, error)
        result['results'].append(item)
    if points:
        with output.open('xb') as handle:
            handle.write(gpx.generate(points, args.segment_gap))
        result['output'] = str(output)
    else:
        result['output'] = None
    code = finish(result)
    emit(result)
    return code


def geotag(args):
    sources = photos(args.photos)
    output = regular_path(args.output)
    if output.exists() or not output.parent.is_dir():
        raise ValueError('Output must be a new directory under an existing parent')
    if any(output == source.parent or source.parent in output.parents for source in sources):
        raise ValueError('Output directory must be outside source photo directories')
    if len({source.name.casefold() for source in sources}) != len(sources):
        raise ValueError('Duplicate basenames; process these inputs in separate runs')
    if any(source.name.casefold() == 'phototrail-report.json' for source in sources):
        raise ValueError('Photo filename conflicts with the report filename')
    tracks = []
    for value in args.gpx:
        path = regular_path(value)
        tracks.append((path, gpx.load(path)))
    zone = metadata.parse_zone(args.timezone)
    result, jobs = report(args.command, args), []
    for source in sources:
        item = dict(source=str(source))
        try:
            original_hash = metadata.digest(source)
            values = metadata.read(source)
            if values.get('File:FileType') not in ('JPEG', 'HEIC'):
                raise metadata.PhotoError('unsupported_format', 'Only JPEG and HEIC copies are writable')
            if source.with_suffix('.xmp').exists() or source.with_suffix('.XMP').exists():
                raise metadata.PhotoError('sidecar_present', 'XMP sidecars are not supported in this release')
            metadata.check_xmp(values)
            if metadata.has_gps(values) and not args.overwrite_existing:
                raise metadata.PhotoError('already_located', 'Existing GPS retained; use --overwrite-existing explicitly')
            stamp = metadata.capture_time(values, zone) + args.time_offset_seconds
            match = gpx.match(tracks, stamp, args.max_gap_seconds)
            if match['status'] != 'matched':
                raise metadata.PhotoError(match['status'], 'Track conflict' if match['status'] == 'ambiguous'
                                          else 'No matching track interval')
            item.update(status='planned', code='matched', match=match,
                        output=str(output / source.name))
            jobs.append((source, values, original_hash, item))
        except (ValueError, OSError, subprocess.SubprocessError) as error:
            failure(item, error)
        result['results'].append(item)
    if args.dry_run:
        result['dry_run'] = True
        code = finish(result)
        emit(result)
        return code
    # Even a wholly skipped run gets a report, but never an overwritten directory.
    output.mkdir(mode=0o700)
    cancelled = False
    try:
        for source, values, original_hash, item in jobs:
            try:
                metadata.write_copy(source, output / source.name, item['match'], values, original_hash)
                item.update(status='written', code='verified')
            except (ValueError, OSError, subprocess.SubprocessError) as error:
                failure(item, error)
                item.pop('output', None)
    except KeyboardInterrupt:
        cancelled = True
    for item in result['results']:
        if item['status'] == 'planned':
            item.update(status='skipped', code='cancelled', reason='Not completed')
            item.pop('output', None)
    code = finish(result)
    if cancelled:
        result['status'] = 'cancelled'
        code = 130
    result['report'] = str(output / 'phototrail-report.json')
    with (output / 'phototrail-report.json').open('x', encoding='utf-8') as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2, allow_nan=False)
    emit(result)
    return code


def main(argv=None):
    parser = Parser(description=__doc__)
    parser.add_argument('--version', action='version', version=VERSION)
    commands = parser.add_subparsers(dest='command', required=True, parser_class=Parser)
    commands.add_parser('check', help='Check local runtime; no installation or writes')
    export = commands.add_parser('export-gpx', help='Located photos to a new GPX file')
    tag = commands.add_parser('geotag', help='GPX to geotagged JPEG/HEIC copies')
    for command in (export, tag):
        command.add_argument('--photos', nargs='+', required=True, help='Files or non-recursive directories')
        command.add_argument('--output', required=True)
        command.add_argument('--timezone', help='Fallback for EXIF without offset, e.g. Asia/Shanghai or +08:00')
    export.add_argument('--assume-wgs84', action='store_true')
    export.add_argument('--segment-gap', type=positive, default=300, help='Seconds; default 300')
    tag.add_argument('--gpx', nargs='+', required=True)
    tag.add_argument('--time-offset-seconds', type=finite, default=0,
                     help='Add to camera time for matching only; slow camera needs positive offset')
    tag.add_argument('--max-gap-seconds', type=positive, default=7200)
    tag.add_argument('--overwrite-existing', action='store_true', help='Replace GPS in output copies only')
    tag.add_argument('--dry-run', action='store_true', help='Read-only matching preview')
    try:
        args = parser.parse_args(argv)
        exiftool = metadata.run(['-ver']).strip()
        if args.command == 'check':
            emit(dict(status='ok', version=VERSION, python=platform.python_version(),
                      platform=platform.system(), exiftool=exiftool,
                      commands=['export-gpx', 'geotag'], writable_formats=['JPEG', 'HEIC']))
            return 0
        return export_gpx(args) if args.command == 'export-gpx' else geotag(args)
    except KeyboardInterrupt:
        emit(dict(status='cancelled', code='cancelled', reason='Interrupted'))
        return 130
    except (ValueError, OSError, ET.ParseError, subprocess.SubprocessError) as error:
        emit(dict(status='error', code=getattr(error, 'code', 'invalid_input'), reason=str(error)))
        return 2


if __name__ == '__main__':
    sys.exit(main())
