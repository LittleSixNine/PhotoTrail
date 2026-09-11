#!/usr/bin/env python3
"""Generate fictional tracks and a preview; no downloaded maps or photos."""
import argparse
from datetime import datetime, timedelta, timezone
import json
import math
from pathlib import Path
from statistics import median
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from extract_gpx import generate_gpx
from preview import write_preview
from track_analysis import Point, Policy, Locator, analyze, distance, unproject, read_gpx

BASE = datetime(2026, 1, 1, tzinfo=timezone.utc)
ORIGIN = Point(BASE, 30, 120)


def point(t, x, y):
    return Point(BASE + timedelta(seconds=t), *unproject((x, y), ORIGIN))


def benchmark():
    # Authored formulas, not observed walks or road-network data.
    profiles = {
        'straight': lambda t: (t, 0),
        'arc': lambda t: (60*math.sin(t/60), 60*(1-math.cos(t/60))),
        'right_angle': lambda t: (min(t, 75), max(0, t-75)),
        'stop': lambda t: (t if t<60 else 60 if t<100 else t-40, 0),
    }
    results = []
    for name, truth in profiles.items():
        for step in (5, 10, 15, 30, 60):
            anchors = [point(t, *truth(t)) for t in range(0, 181, step)]
            report = analyze(anchors)
            locator = Locator(report)
            errors, linear_errors, unresolved = [], [], 0
            for t in range(1, 180):
                if t % step == 0:
                    continue
                actual = locator.locate(BASE + timedelta(seconds=t))
                reference = point(t, *truth(t))
                if actual['latitude'] is None:
                    unresolved += 1
                else:
                    errors.append(distance(reference, Point(reference.time, actual['latitude'], actual['longitude'])))
                before = (t//step)*step
                a, b = truth(before), truth(before+step)
                u = (t-before)/step
                linear_errors.append(distance(reference, point(t, a[0]+(b[0]-a[0])*u, a[1]+(b[1]-a[1])*u)))
            errors.sort()
            results.append({'profile': name, 'sampling_seconds': step, 'inference_threshold_seconds': 15,
                            'candidate_intervals': report['summary']['decisions'].get('infer', 0),
                            'unresolved_queries': unresolved,
                            'median_error_m': round(median(errors), 3) if errors else None,
                            'p95_error_m': round(errors[math.ceil(.95*len(errors))-1], 3) if errors else None,
                            'max_error_m': round(max(errors), 3) if errors else None,
                            'linear_p95_error_m': round(sorted(linear_errors)[math.ceil(.95*len(linear_errors))-1], 3)})
    return {'data_source': 'Authored synthetic formulas only; no real-location observations.',
            'limitation': 'Regression comparison, not real-world accuracy validation or proof of an optimal threshold.',
            'results': results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', help='New directory for fictional GPX, preview and benchmark')
    args = parser.parse_args()
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=False)
    tuples = [(0,-15,-5),(10,0,0),(40,40,20),(55,60,35),(70,60,35),
              (85,61,35),(100,60,36),(140,85,55),(240,100,80),(600,120,120),(610,125,130)]
    records = [{'datetime': p.time, 'latitude': p.lat, 'longitude': p.lon, 'local_date': '2026-01-01'}
               for p in (point(*entry) for entry in tuples)]
    gpx = out / 'synthetic-track.gpx'
    generate_gpx(records, gpx, 'Synthetic track — not a real trip')
    points = read_gpx(gpx)
    write_preview(points, Policy(), out / 'preview.html')
    (out / 'analysis.json').write_text(json.dumps(analyze(points), ensure_ascii=False, indent=2) + '\n')
    (out / 'benchmark.json').write_text(json.dumps(benchmark(), ensure_ascii=False, indent=2) + '\n')
    print(out / 'preview.html')


if __name__ == '__main__':
    main()
