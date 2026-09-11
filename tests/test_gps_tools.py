"""Synthetic regression checks; no personal photos, services, or API keys."""
from datetime import datetime, timedelta, timezone
import hashlib
import json
import math
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zlib

import extract_gpx as extract
from gps_tools import geotag_copies
from preview import write_preview
from track_analysis import Point, Policy, Locator, analyze, read_gpx, unproject, prepare_road_requests

BASE = datetime(2026, 1, 1, tzinfo=timezone.utc)
ORIGIN = Point(BASE, 30, 120)
NS = {'g': 'http://www.topografix.com/GPX/1/1'}


def point(seconds, x, y=0, segment=0):
    lat, lon = unproject((x, y), ORIGIN)
    return Point(BASE + timedelta(seconds=seconds), lat, lon, segment)


def photo(**changes):
    data = {'SourceFile': 'synthetic.jpg', 'GPSLatitude': 30, 'GPSLongitude': 120,
            'DateTimeOriginal': '2026:01:01 10:00:00', 'OffsetTimeOriginal': '+08:00'}
    return {**data, **changes}


def png(path):
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(b'\0\x40\x60\x80')) + chunk(b'IEND', b''))


class ExtractionTests(unittest.TestCase):
    def test_per_photo_timezone_and_fallback(self):
        data = [photo(OffsetTimeOriginal='+08:00'), photo(OffsetTimeOriginal='+09:00'),
                photo(OffsetTimeOriginal=None)]
        result = extract.extract_gps_photos(data, 5.5)
        self.assertEqual([p['datetime'].strftime('%H:%M') for p in result], ['01:00', '02:00', '04:30'])

    def test_missing_and_invalid_zone_fail(self):
        for zone in (None, '+08:75', '+15:00', 'unknown'):
            with self.subTest(zone=zone), self.assertRaises(ValueError):
                extract.extract_gps_photos([photo(OffsetTimeOriginal=zone)])
        for offset in (float('nan'), float('inf'), 24, .001):
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                extract.checked_timezone(offset)

    def test_local_date_preserved(self):
        result = extract.extract_gps_photos([photo(DateTimeOriginal='2026:01:02 00:30:00')])
        self.assertEqual(result[0]['datetime'].date().isoformat(), '2026-01-01')
        self.assertEqual(list(extract.group_by_date(result)), ['2026-01-02'])

    def test_datetime_fraction_and_digitized_offset(self):
        dt = extract.photo_datetime(photo(SubSecTimeOriginal='125'))
        self.assertEqual(dt.microsecond, 125000)
        dt = extract.photo_datetime({'CreateDate': '2026:01:01 10:00:00', 'OffsetTimeDigitized': '-05:00'})
        self.assertEqual(dt.utcoffset(), timedelta(hours=-5))
        dt = extract.photo_datetime({'DateTimeOriginal': '2026-01-01T10:00:00+05:30'})
        self.assertEqual(dt.utcoffset(), timedelta(hours=5.5))

    def test_coordinate_validation_and_refs(self):
        self.assertEqual(extract.parse_gps_coords(photo(GPSLatitudeRef='S', GPSLongitudeRef='W')), (-30, -120))
        for lat, lon in ((999, 0), (0, 180), (float('nan'), 0), (0, float('inf'))):
            self.assertIsNone(extract.parse_gps_coords({'GPSLatitude': lat, 'GPSLongitude': lon}))
        self.assertEqual(extract.parse_gps_coords({'GPSLatitude': '30 deg 0\' 0.00" S',
                                                  'GPSLongitude': '120 deg 0\' 0.00" W'}), (-30, -120))

    def test_gpx_numeric_altitude_zero_below_and_gap(self):
        result = extract.extract_gps_photos([photo(GPSAltitude=0),
                  photo(DateTimeOriginal='2026:01:01 10:00:10', GPSAltitude=20, GPSAltitudeRef=1),
                  photo(DateTimeOriginal='2026:01:01 10:10:00', GPSAltitude='50 m Above Sea Level')])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'track.gpx'
            extract.generate_gpx(result, path)
            root = ET.parse(path)
            self.assertEqual([e.text for e in root.findall('.//g:ele', NS)], ['0', '-20'])
            self.assertEqual(len(root.findall('.//g:trkseg', NS)), 2)
            self.assertTrue(all(e.text.endswith('Z') for e in root.findall('.//g:time', NS)))
            self.assertEqual(len(read_gpx(path)), 3)
            with self.assertRaises(FileExistsError):
                extract.generate_gpx(result, path)

    def test_naive_time_cannot_be_written(self):
        record = {'datetime': datetime(2026, 1, 1), 'latitude': 30, 'longitude': 120}
        with tempfile.TemporaryDirectory() as tmp, self.assertRaises(ValueError):
            extract.generate_gpx([record], Path(tmp) / 'invalid.gpx')


class TrajectoryTests(unittest.TestCase):
    def test_threshold_is_strict_and_dense_never_calls_curve(self):
        for seconds in (5, 10, 15):
            with self.subTest(seconds=seconds), patch('track_analysis.curve_samples', side_effect=AssertionError('unnecessary inference')):
                self.assertEqual(analyze([point(0, 0), point(seconds, 10)])['intervals'][0]['decision'], 'dense')
        self.assertEqual(analyze([point(0, 0), point(15.01, 10)])['intervals'][0]['decision'], 'infer')
        self.assertEqual(analyze([point(0, 0), point(20, 10)], Policy(infer_after=30))['intervals'][0]['decision'], 'dense')

    def test_dense_tracks_generate_no_road_requests(self):
        points = [point(t,t) for t in range(0,61,5)]
        self.assertEqual(prepare_road_requests(points,analyze(points))['requests'], [])

    def test_road_context_excludes_breaks_and_has_no_credentials(self):
        points = [point(0,0),point(5,5),point(35,25),point(40,30),point(400,50),point(430,70)]
        output = prepare_road_requests(points,analyze(points))
        self.assertFalse(output['sent'])
        self.assertEqual(len(output['requests']),2)
        self.assertEqual(output['requests'][0]['end_index'],3)
        self.assertEqual(output['requests'][1]['start_index'],4)
        for request in output['requests']:
            self.assertNotIn('ak',request['form'])
            self.assertEqual(request['form']['coord_type_output'],'gcj02')
            self.assertTrue(all(p['coord_type_input']=='wgs84' for p in json.loads(request['form']['point_list'])))

    def test_candidate_review_and_break_boundaries(self):
        for seconds, expected in ((60, 'infer'), (60.01, 'review'), (300, 'review'), (300.01, 'gap')):
            with self.subTest(seconds=seconds):
                r = analyze([point(0, 0), point(seconds, 20)])
                self.assertEqual(r['intervals'][0]['decision'], expected)
                loc = Locator(r).locate(BASE + timedelta(seconds=seconds / 2))
                self.assertEqual(loc['latitude'] is None, expected in ('review', 'gap'))

    def test_dense_distance_does_not_force_inference(self):
        r = analyze([point(0, 0), point(15, 40)])
        self.assertEqual(r['intervals'][0]['decision'], 'review')
        self.assertEqual(r['intervals'][0]['samples'], [])

    def test_explicit_segment_boundary_and_no_extrapolation(self):
        report = analyze([point(0, 0), point(10, 10, segment=1)])
        for seconds in (-1, 5, 11):
            self.assertIsNone(Locator(report).locate(BASE + timedelta(seconds=seconds))['latitude'])
        self.assertEqual(Locator(report).locate(BASE)['status'], 'recorded')

    def test_stationary_requires_dense_observations(self):
        p = [point(0, 0), point(15, 1), point(30, 0)]
        report = analyze(p)
        self.assertEqual([r['decision'] for r in report['intervals']], ['stationary', 'stationary'])
        self.assertEqual(Locator(report).locate(BASE + timedelta(seconds=20))['method'], 'stationary')
        self.assertNotEqual(analyze([point(0, 0), point(40, 0)])['intervals'][0]['decision'], 'stationary')

    def test_jump_not_smoothened(self):
        report = analyze([point(0, 0), point(1, 1000), point(2, 1)])
        self.assertTrue(all(r['decision'] == 'jump' for r in report['intervals']))
        self.assertTrue(Locator(report).locate(BASE+timedelta(seconds=1))['requires_review'])

    def test_time_aware_curve_and_original_anchors(self):
        points = [point(0, -15, -5), point(10, 0), point(40, 40, 20), point(55, 60, 35)]
        report = analyze(points)
        self.assertEqual(report['intervals'][1]['method'], 'curve')
        result = Locator(report).locate(BASE + timedelta(seconds=25))
        self.assertTrue(result['requires_review'])
        self.assertEqual(result['method'], 'curve')
        for p in points:
            actual = Locator(report).locate(p.time)
            self.assertEqual((actual['latitude'], actual['longitude']), (p.lat, p.lon))

    def test_curve_does_not_cross_neighbor_gap(self):
        report = analyze([point(0, -10), point(301, 0), point(331, 20), point(341, 30)])
        self.assertEqual(report['intervals'][1]['method'], 'linear_candidate')

    def test_nearby_sampling_warning(self):
        report = analyze([point(0, 0), point(5, 2), point(35, 20), point(40, 22)])
        self.assertEqual(report['intervals'][1]['nearby_median_seconds'], 5)
        self.assertIn('三倍', report['intervals'][1]['reason'])

    def test_bad_policy_and_query_timezone(self):
        for kw in ({'infer_after':0}, {'infer_after':61}, {'max_speed':float('nan')}, {'max_infer_gap':301}):
            with self.subTest(kw=kw), self.assertRaises(ValueError):
                Policy(**kw)
        with self.assertRaises(ValueError):
            Locator(analyze([point(0, 0)])).locate('2026-01-01T00:00:00')

    def test_dateline_uses_short_path(self):
        p = [Point(BASE, 0, 179.9999), Point(BASE+timedelta(seconds=15), 0, -179.9999)]
        loc = Locator(analyze(p)).locate(BASE+timedelta(seconds=7.5))
        self.assertAlmostEqual(abs(loc['longitude']), 180, places=5)

    def test_gpx_conflicting_time_and_missing_zone(self):
        template = '<gpx><trk><trkseg><trkpt lat="30" lon="120"><time>{a}</time></trkpt><trkpt lat="31" lon="120"><time>{b}</time></trkpt></trkseg></trk></gpx>'
        for a,b in (('2026-01-01T00:00:00Z','2026-01-01T00:00:00Z'),
                    ('2026-01-01T00:00:00','2026-01-01T00:00:05Z'),
                    ('2026-01-01T00:00:05Z','2026-01-01T00:00:00Z')):
            with tempfile.TemporaryDirectory() as tmp:
                path=Path(tmp)/'bad.gpx';path.write_text(template.format(a=a,b=b))
                with self.assertRaises(ValueError): read_gpx(path)

    def test_offline_preview_and_threshold_comparisons(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'preview.html'
            write_preview([point(0,0),point(20,10)],Policy(),path)
            text=path.read_text()
            self.assertIn('30.0', text)
            self.assertNotIn('<script src=', text)
            self.assertNotIn('fetch(', text)
            payload=text.split('<script type="application/json" id="data">')[1].split('</script>')[0]
            data=json.loads(payload)
            self.assertEqual(data['reports']['15.0']['intervals'][0]['decision'],'infer')
            self.assertEqual(data['reports']['30.0']['intervals'][0]['decision'],'dense')


@unittest.skipUnless(shutil.which('exiftool'), 'ExifTool not installed')
class ExifToolIntegrationTests(unittest.TestCase):
    def test_numeric_exif_extraction_and_copy_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'photos';source.mkdir()
            gps=source/'with.png';target=source/'without.png';png(gps);png(target)
            subprocess.run(['exiftool','-overwrite_original','-DateTimeOriginal=2026:01:01 08:00:05',
                            '-OffsetTimeOriginal=+08:00',str(gps),str(target)],check=True,capture_output=True)
            subprocess.run(['exiftool','-overwrite_original','-GPSLatitude=30','-GPSLatitudeRef=S',
                            '-GPSLongitude=120','-GPSLongitudeRef=W','-GPSAltitude=20','-GPSAltitudeRef#=1',str(gps)],check=True,capture_output=True)
            original_hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in source.iterdir()}
            metadata=extract.run_exiftool(source)
            extracted=extract.extract_gps_photos(metadata)
            self.assertEqual(len(extracted),1)
            self.assertEqual((extracted[0]['latitude'],extracted[0]['longitude'],extracted[0]['altitude']),(-30,-120,-20))
            report=analyze([Point(BASE,-30,-120),Point(BASE+timedelta(seconds=10),-30.0001,-120)])
            result=geotag_copies(source,root/'copies',report)
            self.assertEqual((result['written'],result['failed']),(1,0))
            self.assertTrue((root/'copies'/'without.png').exists())
            self.assertFalse((root/'copies'/'with.png').exists())
            self.assertEqual(original_hashes,{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in source.iterdir()})
            with self.assertRaises(ValueError): geotag_copies(source,root/'copies',report)
            with self.assertRaises(ValueError): geotag_copies(source,source/'copies',report)

    def test_inferred_positions_require_explicit_option(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'photos';source.mkdir();image=source/'candidate.png';png(image)
            subprocess.run(['exiftool','-overwrite_original','-DateTimeOriginal=2026:01:01 08:00:15',
                            '-OffsetTimeOriginal=+08:00',str(image)],check=True,capture_output=True)
            report=analyze([point(0,0),point(30,20)])
            before=image.read_bytes()
            self.assertEqual(geotag_copies(source,root/'blocked',report)['written'],0)
            self.assertFalse((root/'blocked').exists())
            self.assertEqual(geotag_copies(source,root/'approved',report,allow_inferred=True)['written'],1)
            self.assertEqual(image.read_bytes(),before)


if __name__ == '__main__':
    unittest.main()
