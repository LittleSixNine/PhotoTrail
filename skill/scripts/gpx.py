"""GPX rules adapted from PhotoTrail; see ../INSTALL.md and ../LICENSE."""

import math
from datetime import datetime, timezone
from pathlib import Path
import xml.etree.ElementTree as ET


def coordinate(lat, lon):
    return (math.isfinite(lat) and math.isfinite(lon)
            and abs(lat) <= 90 and abs(lon) <= 180)


def distance(a, b):
    lat1, lat2 = math.radians(a['lat']), math.radians(b['lat'])
    dlat = lat2 - lat1
    dlon = math.radians(b['lon'] - a['lon'])
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6371008.8 * 2 * math.asin(math.sqrt(min(1, max(0, h))))


def load(path):
    data = Path(path).read_text(encoding='utf-8-sig')
    if '\x00' in data or '<!DOCTYPE' in data.upper() or '<!ENTITY' in data.upper():
        raise ValueError('GPX must not contain DTD or entity declarations')
    root = ET.fromstring(data)
    if root.tag not in ('gpx', '{http://www.topografix.com/GPX/1/1}gpx',
                        '{http://www.topografix.com/GPX/1/0}gpx'):
        raise ValueError('Not a GPX document')
    prefix = root.tag[:-3]
    segments = []
    for segment in root.findall(f'{prefix}trk/{prefix}trkseg'):
        points = []
        for node in segment.findall(f'{prefix}trkpt'):
            try:
                lat, lon = float(node.attrib['lat']), float(node.attrib['lon'])
                stamp = datetime.fromisoformat(node.findtext(prefix + 'time', '').replace('Z', '+00:00'))
                if not coordinate(lat, lon) or stamp.utcoffset() is None:
                    raise ValueError('Invalid point')
                elevation = node.findtext(prefix + 'ele')
                elevation = float(elevation) if elevation is not None else None
                if elevation is not None and not math.isfinite(elevation):
                    elevation = None
                points.append(dict(lat=lat, lon=lon, time=stamp.timestamp(), elevation=elevation))
            except (ValueError, KeyError, OverflowError):
                # Invalid samples break continuity: never interpolate across them.
                if points:
                    segments.append(points)
                points = []
        if points:
            segments.append(points)
    if not segments:
        raise ValueError('GPX has no valid timed track points')
    return segments


def match_track(segments, timestamp, maximum_gap):
    exact, interpolated = [], []
    for points in segments:
        for point in points:
            if point['time'] == timestamp:
                exact.append(dict(point, method='recorded', time_delta_seconds=0))
        for before, after in zip(points, points[1:]):
            gap = after['time'] - before['time']
            if not (0 < gap <= maximum_gap and before['time'] < timestamp < after['time']):
                continue
            fraction = (timestamp - before['time']) / gap
            delta = (after['lon'] - before['lon'] + 540) % 360 - 180
            elevation = None
            if before['elevation'] is not None and after['elevation'] is not None:
                elevation = before['elevation'] + (after['elevation'] - before['elevation']) * fraction
            interpolated.append(dict(
                lat=before['lat'] + (after['lat'] - before['lat']) * fraction,
                lon=(before['lon'] + delta * fraction + 540) % 360 - 180,
                elevation=elevation, method='linear',
                time_delta_seconds=min(timestamp - before['time'], after['time'] - timestamp)))
    candidates = exact or interpolated
    if not candidates:
        return {'status': 'unmatched'}
    if any(distance(candidates[0], other) > 1 for other in candidates[1:]):
        return {'status': 'ambiguous'}
    return dict(candidates[0], status='matched')


def match(tracks, timestamp, maximum_gap=7200):
    candidates = []
    for source, segments in tracks:
        result = match_track(segments, timestamp, maximum_gap)
        if result['status'] == 'ambiguous':
            return result
        if result['status'] == 'matched':
            candidates.append(dict(result, track=str(source)))
    if not candidates:
        return {'status': 'unmatched'}
    if any(distance(candidates[0], other) > 1 for other in candidates[1:]):
        return {'status': 'ambiguous'}
    return candidates[0]


def generate(points, segment_gap=300):
    root = ET.Element('gpx', version='1.1', creator='PhotoTrail skill',
                      xmlns='http://www.topografix.com/GPX/1/1')
    track = ET.SubElement(root, 'trk')
    ET.SubElement(track, 'name').text = 'PhotoTrail Photos'
    previous = None
    for point in sorted(points, key=lambda item: item['time']):
        if previous is None or point['time'] - previous > segment_gap:
            segment = ET.SubElement(track, 'trkseg')
        node = ET.SubElement(segment, 'trkpt', lat=f"{point['lat']:.8f}", lon=f"{point['lon']:.8f}")
        if point.get('elevation') is not None:
            ET.SubElement(node, 'ele').text = str(point['elevation'])
        ET.SubElement(node, 'time').text = datetime.fromtimestamp(
            point['time'], timezone.utc).isoformat().replace('+00:00', 'Z')
        ET.SubElement(node, 'name').text = point['name']
        previous = point['time']
    ET.indent(root)
    return ET.tostring(root, encoding='utf-8', xml_declaration=True)
