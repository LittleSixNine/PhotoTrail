#!/usr/bin/env python3
"""PhotoTrail: extraction, conservative analysis, preview and copy-only geotagging."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

import extract_gpx
from preview import write_preview
from track_analysis import Locator, Policy, analyze, read_gpx, prepare_road_requests


def write_json(data, output=None):
    text = json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
    if output:
        with Path(output).open("x", encoding="utf-8") as handle:
            handle.write(text)
    else:
        print(text, end="")


def photo_locations(photos_dir, report, fallback=None):
    if fallback is not None:
        extract_gpx.checked_timezone(fallback)
    locator = Locator(report)
    results = []
    for photo in extract_gpx.run_exiftool(photos_dir):
        item = {"source": photo.get("SourceFile", ""), "status": "unresolved"}
        if extract_gpx.parse_gps_coords(photo) is not None:
            results.append({**item, "status": "skipped", "reason": "照片已有 GPS。"})
            continue
        try:
            when = extract_gpx.photo_datetime(photo, fallback)
            if when is None:
                raise ValueError("照片缺少有效拍摄时间。")
            item.update(locator.locate(when))
        except ValueError as exc:
            item["reason"] = str(exc)
        results.append(item)
    return results


def geotag_copies(photos_dir, output, report, fallback=None, allow_inferred=False):
    """Only modify new copies in a new directory; verify coordinates by reading back."""
    source_root, output = Path(photos_dir).resolve(), Path(output).resolve()
    if output == source_root or source_root in output.parents:
        raise ValueError("输出必须位于源照片目录之外。")
    if output.exists():
        raise ValueError("输出目录已存在，请指定一个新目录以保留原有文件。")
    results = photo_locations(source_root, report, fallback)
    supported = {'.jpg', '.jpeg', '.png', '.tif', '.tiff', '.heic', '.arw', '.dng', '.nef', '.cr2', '.cr3', '.raf'}
    pending = []
    for item in results:
        if item.get("latitude") is None or item["status"] == "skipped":
            continue
        if item.get("requires_review") and not allow_inferred:
            item.update(status="skipped", reason="候选位置需要检查，默认不写入；确认后可使用 --allow-inferred。")
            continue
        # Jump-adjacent recorded points are not validated by opting into curves.
        if item.get("method") == "recorded" and item.get("requires_review"):
            item.update(status="skipped", reason="邻近异常位移的原始点不能自动写入。")
            continue
        source = Path(item["source"])
        resolved = source.resolve()
        if source.is_symlink() or source_root not in resolved.parents or not resolved.is_file():
            item.update(status="skipped", reason="源文件不在指定目录内，或为符号链接。")
            continue
        if resolved.suffix.lower() not in supported:
            item.update(status="skipped", reason="文件格式不在照片写入列表中。")
            continue
        pending.append((item, resolved, resolved.relative_to(source_root)))
    if not pending:
        return {"written": 0, "failed": 0, "results": results}
    output.mkdir(parents=True, exist_ok=False)
    written = failed = 0
    for item, source, relative in pending:
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        try:
            # Exclusive creation avoids replacing any concurrent writer's file.
            with source.open('rb') as incoming, target.open('xb') as outgoing:
                shutil.copyfileobj(incoming, outgoing)
            shutil.copystat(source, target)
            lat, lon = item["latitude"], item["longitude"]
            cmd = ["exiftool", "-overwrite_original", "-P", f"-GPSLatitude={abs(lat):.9f}",
                   "-GPSLatitudeRef=" + ("S" if lat < 0 else "N"), f"-GPSLongitude={abs(lon):.9f}",
                   "-GPSLongitudeRef=" + ("W" if lon < 0 else "E"), "-GPSMapDatum=WGS-84", str(target)]
            subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=60)
            check = subprocess.run(["exiftool", "-json", "-n", "-GPSLatitude", "-GPSLatitudeRef",
                                    "-GPSLongitude", "-GPSLongitudeRef", str(target)],
                                   capture_output=True, text=True, check=True, timeout=60)
            coords = extract_gpx.parse_gps_coords(json.loads(check.stdout)[0])
            if coords is None or abs(coords[0]-lat) > 1e-6 or abs(coords[1]-lon) > 1e-6:
                raise ValueError("写入后坐标回读不一致。")
            item.update(status="written", output=str(target))
            written += 1
        except (OSError, ValueError, subprocess.SubprocessError) as exc:
            item.update(status="failed", reason=f"副本写入／验证失败：{type(exc).__name__}", output=str(target))
            failed += 1
    result = {"written": written, "failed": failed, "results": results}
    write_json(result, output / "geotag-report.json")
    return result


def add_track_arguments(parser):
    parser.add_argument("gpx", help="带时间的 GPX 轨迹")
    parser.add_argument("--infer-after", type=float, default=15, help="超过此秒数才考虑补线（默认 15）")
    parser.add_argument("--max-infer-gap", type=float, default=60, help="自动生成候选的最大间隔秒数（默认 60）")
    parser.add_argument("--break-after", type=float, default=300, help="断点上限秒数（默认 300）")
    parser.add_argument("--dense-distance", type=float, default=30, help="密集区间位移上限，米（默认 30）")
    parser.add_argument("--max-speed", type=float, default=3, help="步行速度检查值，米/秒（默认 3）")


def main(argv=None):
    parser = argparse.ArgumentParser(description="PhotoTrail：提取、分析、离线预览与副本写入")
    subs = parser.add_subparsers(dest="command", required=True)
    extract_parser = subs.add_parser("extract", help="从照片提取 GPX（不修改照片）")
    extract_gpx.add_extract_arguments(extract_parser)
    for command, help_text in (("analyze", "输出区间分类与推理依据"),
                               ("prepare-road-requests", "仅生成稀疏区间的道路匹配请求草稿，不上传"),
                               ("preview", "生成离线交互预览，可比较 5/10/15/30/60 秒阈值"),
                               ("locate", "按拍摄时间估算位置，不写照片"),
                               ("geotag", "只对新目录中的照片副本写入 GPS")):
        child = subs.add_parser(command, help=help_text)
        add_track_arguments(child)
        child.add_argument("-o", "--output", required=command in ("preview", "geotag"),
                           help="新的输出文件；geotag 为新的副本目录")
        if command == "locate":
            source = child.add_mutually_exclusive_group(required=True)
            source.add_argument("--time", action="append", help="带时区的 ISO 拍摄时间，可重复")
            source.add_argument("--photos", help="只读取目标照片元数据，跳过已有 GPS 的照片")
        if command == "geotag":
            child.add_argument("--photos", required=True, help="源照片目录")
            child.add_argument("--allow-inferred", action="store_true", help="允许把已检查的推理候选写入副本")
        if command in ("locate", "geotag"):
            child.add_argument("--timezone", type=float, help="照片缺失时区时的后备小时数")
    args = parser.parse_args(argv)
    try:
        if args.command == "extract":
            extract_gpx.extract(args.photos_dir, args.output, args.single_file, args.timezone)
            return 0
        policy = Policy(args.infer_after, args.max_infer_gap, args.break_after,
                        args.dense_distance, args.max_speed)
        points = read_gpx(args.gpx)
        if args.command == "preview":
            write_preview(points, policy, args.output)
            print(f"离线预览已保存：{args.output}")
            return 0
        report = analyze(points, policy)
        if args.command == "analyze":
            write_json(report, args.output)
        elif args.command == "prepare-road-requests":
            write_json(prepare_road_requests(points, report), args.output)
        elif args.command == "locate":
            locator = Locator(report)
            result = (photo_locations(args.photos, report, args.timezone) if args.photos
                      else [locator.locate(t) for t in args.time])
            write_json(result, args.output)
        else:
            result = geotag_copies(args.photos, args.output, report, args.timezone, args.allow_inferred)
            write_json(result)
            return 1 if result["failed"] else 0
        return 0
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        parser.exit(1, f"错误：{exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
