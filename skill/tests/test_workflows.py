"""Run: python3 -B -m unittest discover -s skill/tests -v.

Fixtures are generated solid-color images, not user photographs.
Integration tests require ExifTool and fail if the dependency is missing.
"""

from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

SKILL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL / 'scripts'))
import gpx
import metadata

START = datetime(2026, 1, 1, tzinfo=timezone.utc).timestamp()


def point(seconds, lat=10, lon=20, elevation=100):
    return dict(time=START + seconds, lat=lat, lon=lon, elevation=elevation, name='A & B')


class AlgorithmTests(unittest.TestCase):
    def test_swift_midpoint_reference(self):
        # Same endpoints/expected result as GpxTrackLog's Swift midpoint test.
        result = gpx.match([('one', [[point(0), point(60, 20, 40, 200)]])], START + 30)
        self.assertEqual((result['lat'], result['lon'], result['elevation']), (15, 30, 150))
        self.assertEqual(result['method'], 'linear')

    def test_no_extrapolation_or_cross_segment(self):
        tracks = [('one', [[point(0)], [point(60)]])]
        for seconds in (-1, 30, 61):
            self.assertEqual(gpx.match(tracks, START + seconds)['status'], 'unmatched')

    def test_gap_limit_and_dateline(self):
        tracks = [('one', [[point(0, lon=179), point(60, lon=-179)]])]
        self.assertEqual(gpx.match(tracks, START + 30, 59)['status'], 'unmatched')
        self.assertEqual(gpx.match(tracks, START + 30, 60)['lon'], -180)

    def test_conflicting_tracks_and_duplicate_times(self):
        a, b = point(0), point(0, lat=30)
        for tracks in ([('one', [[a, b]])], [('one', [[a]]), ('two', [[b]])]):
            self.assertEqual(gpx.match(tracks, START)['status'], 'ambiguous')

    def test_recorded_point_preferred_within_track(self):
        tracks = [('one', [[point(0)], [point(-30, lat=30), point(30, lat=40)]])]
        self.assertEqual(gpx.match(tracks, START)['lat'], 10)

    def test_time_offset_precedence_and_dst(self):
        data = {'ExifIFD:DateTimeOriginal': '2026:01:01 08:00:00'}
        self.assertEqual(metadata.capture_time(data, metadata.parse_zone('Asia/Shanghai')), START)
        data['ExifIFD:OffsetTimeOriginal'] = '+08:00'
        self.assertEqual(metadata.capture_time(data, timezone.utc), START)
        for raw in ('2026:03:08 02:30:00', '2026:11:01 01:30:00'):
            with self.assertRaises(metadata.PhotoError):
                metadata.capture_time({'ExifIFD:DateTimeOriginal': raw},
                                      metadata.parse_zone('America/New_York'))

    def test_missing_time_timezone_and_datum(self):
        with self.assertRaises(metadata.PhotoError):
            metadata.capture_time({})
        with self.assertRaises(metadata.PhotoError):
            metadata.capture_time({'ExifIFD:DateTimeOriginal': '2026:01:01 00:00:00'})
        values = {'Composite:GPSLatitude': 10, 'Composite:GPSLongitude': 20}
        with self.assertRaises(metadata.PhotoError):
            metadata.position(values)
        self.assertEqual(metadata.position(values, True)['lat'], 10)
        values['GPS:GPSMapDatum'] = 'GCJ-02'
        with self.assertRaises(metadata.PhotoError):
            metadata.position(values, True)

    def test_gpx_roundtrip_sort_segments_and_invalid_break(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'track.gpx'
            path.write_bytes(gpx.generate([point(400), point(0), point(20)]))
            segments = gpx.load(path)
            self.assertEqual([len(segment) for segment in segments], [2, 1])
            root = ET.fromstring(path.read_bytes())
            self.assertEqual(root.find('.//{*}name').text, 'PhotoTrail Photos')
            path.write_text('<gpx><trk><trkseg><trkpt lat="10" lon="20"><time>2026-01-01T00:00:00Z</time></trkpt>'
                            '<trkpt lat="NaN" lon="20"/><trkpt lat="10" lon="20">'
                            '<time>2026-01-01T00:01:00Z</time></trkpt></trkseg></trk></gpx>')
            self.assertEqual(gpx.match([('x', gpx.load(path))], START + 30)['status'], 'unmatched')


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.input = self.root / '照片 input'
        self.input.mkdir()
        self.track = self.root / 'track.gpx'
        self.track.write_bytes(gpx.generate([point(0, lat=-10, lon=-20, elevation=-5),
                                             point(60, lat=-12, lon=-22, elevation=-15)]))

    def photo(self, name='照片 $ name.jpg', date='2026:01:01 00:00:30', offset='+00:00'):
        suffix = Path(name).suffix
        target = self.input / name
        shutil.copyfile(SKILL / 'tests' / 'fixtures' / ('blank' + suffix), target)
        metadata.run(['-overwrite_original', f'-DateTimeOriginal={date}',
                      f'-OffsetTimeOriginal={offset}', str(target)])
        return target

    def cli(self, *args, expected=0, script=None):
        call = subprocess.run([sys.executable, '-B', str(script or SKILL / 'scripts' / 'phototrail.py'),
                               *map(str, args)], capture_output=True, text=True)
        self.assertEqual(call.returncode, expected, call.stdout + call.stderr)
        return json.loads(call.stdout)

    def tag(self, output='out', extra=(), expected=0):
        return self.cli('geotag', '--photos', self.input, '--gpx', self.track,
                        '--output', self.root / output, *extra, expected=expected)

    def test_jpeg_heic_write_and_gpx_roundtrip(self):
        files = [self.photo(), self.photo('image.heic')]
        hashes = [metadata.digest(path) for path in files]
        result = self.tag()
        self.assertEqual(result['counts'], {'written': 2})
        for path, original_hash in zip(files, hashes):
            self.assertEqual(metadata.digest(path), original_hash)
            values = metadata.read(self.root / 'out' / path.name)
            actual = metadata.position(values)
            self.assertAlmostEqual(actual['lat'], -11)
            self.assertAlmostEqual(actual['lon'], -21)
            self.assertAlmostEqual(actual['elevation'], -10)
            self.assertEqual(metadata.capture_time(values), START + 30)
        exported = self.cli('export-gpx', '--photos', self.root / 'out',
                            '--output', self.root / 'photos.gpx')
        self.assertEqual(exported['counts'], {'exported': 2})
        self.assertEqual(len(gpx.load(self.root / 'photos.gpx')[0]), 2)

    def test_dry_run_no_output(self):
        source = self.photo()
        before = metadata.digest(source)
        self.assertEqual(self.tag(extra=['--dry-run'])['counts'], {'planned': 1})
        self.assertFalse((self.root / 'out').exists())
        self.assertEqual(metadata.digest(source), before)

    def test_existing_gps_skip_and_explicit_overwrite(self):
        source = self.photo()
        metadata.run(['-overwrite_original', '-GPSLatitude=5', '-GPSLatitudeRef=N',
                      '-GPSLongitude=6', '-GPSLongitudeRef=E', str(source)])
        self.assertEqual(self.tag(expected=3)['results'][0]['code'], 'already_located')
        self.assertEqual(self.tag('new', ['--overwrite-existing'])['counts'], {'written': 1})

    def test_offset_crosses_day_without_rewriting_time(self):
        source = self.photo(date='2025:12:31 23:58:30')
        self.tag(extra=['--time-offset-seconds', '120'])
        values = metadata.read(self.root / 'out' / source.name)
        self.assertEqual(values['ExifIFD:DateTimeOriginal'], '2025:12:31 23:58:30')
        self.assertAlmostEqual(metadata.position(values)['lat'], -11)

    def test_missing_timezone_partial_failure_and_sidecar(self):
        self.photo('good.jpg')
        self.photo('missing.jpg', offset='')
        self.photo('paired.jpg')
        (self.input / 'paired.xmp').write_text('sidecar')
        result = self.tag(expected=3)
        codes = {item['code'] for item in result['results']}
        self.assertTrue({'verified', 'missing_timezone', 'sidecar_present', 'unsupported_format'} <= codes)

    def test_refuse_output_reuse_nested_and_duplicate_names(self):
        self.photo()
        self.tag()
        saved = (self.root / 'out' / 'phototrail-report.json').read_bytes()
        self.tag(expected=2)
        self.assertEqual((self.root / 'out' / 'phototrail-report.json').read_bytes(), saved)
        self.cli('geotag', '--photos', self.input, '--gpx', self.track,
                 '--output', self.input / 'nested', expected=2)
        other = self.root / 'other'
        shutil.copytree(self.input, other)
        self.cli('geotag', '--photos', self.input, other, '--gpx', self.track,
                 '--output', self.root / 'duplicate', expected=2)

    def test_no_point_no_gpx_output(self):
        self.photo()
        result = self.cli('export-gpx', '--photos', self.input,
                          '--output', self.root / 'empty.gpx', expected=3)
        self.assertIsNone(result['output'])
        self.assertFalse((self.root / 'empty.gpx').exists())

    def test_embedded_xmp_gps_is_not_silently_left_inconsistent(self):
        source = self.photo()
        metadata.run(['-overwrite_original', '-XMP-exif:GPSLatitude=30',
                      '-XMP-exif:GPSLongitude=40', str(source)])
        self.assertEqual(self.tag(expected=3)['results'][0]['code'], 'unsupported_xmp_gps')

    def test_changed_source_and_failed_copy_cleanup(self):
        source = self.photo()
        values, original_hash = metadata.read(source), metadata.digest(source)
        with source.open('ab') as handle:
            handle.write(b'changed')
        target = self.root / 'copy.jpg'
        with self.assertRaises(metadata.PhotoError):
            metadata.write_copy(source, target, point(0), values, original_hash)
        self.assertFalse(target.exists())

    def test_write_failure_and_interrupt_cleanup(self):
        source = self.photo()
        values, original_hash = metadata.read(source), metadata.digest(source)
        for error in (metadata.PhotoError('exiftool_error', 'failure'), KeyboardInterrupt()):
            target = self.root / 'copy.jpg'
            with patch.object(metadata, 'run', side_effect=error):
                with self.assertRaises(type(error)):
                    metadata.write_copy(source, target, point(0), values, original_hash)
            self.assertFalse(target.exists())

    def test_unknown_timezone_invalid_gpx_and_symlink(self):
        self.photo()
        self.tag(extra=['--timezone', 'Not/AZone'], expected=2)
        self.track.write_text('<gpx><broken>')
        self.tag(expected=2)
        link = self.root / 'link'
        link.symlink_to(self.input, target_is_directory=True)
        self.cli('export-gpx', '--photos', link, '--output', self.root / 'x.gpx', expected=2)

    def test_standalone_install(self):
        installed = self.root / '独立安装' / 'phototrail'
        shutil.copytree(SKILL, installed, ignore=shutil.ignore_patterns('__pycache__'))
        script = installed / 'scripts' / 'phototrail.py'
        self.cli('check', script=script)
        self.photo()
        self.cli('geotag', '--photos', self.input, '--gpx', self.track,
                 '--output', self.root / 'standalone', script=script)
        self.cli('export-gpx', '--photos', self.root / 'standalone',
                 '--output', self.root / 'standalone.gpx', script=script)


if __name__ == '__main__':
    unittest.main()
