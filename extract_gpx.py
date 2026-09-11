#!/usr/bin/env python3
"""Read photograph metadata with ExifTool and write GPX in UTC (Python 3.9+)."""
import argparse
from collections import defaultdict
from datetime import datetime, timedelta, timezone
import json
import math
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET


def run_exiftool(photos_dir):
    """Read numeric EXIF values; never write metadata or execute a shell."""
    photos_dir = Path(photos_dir).resolve()
    if not photos_dir.is_dir():
        raise ValueError(f"照片文件夹不存在：{photos_dir}")
    cmd = ["exiftool", "-json", "-n", "-GPSLatitude", "-GPSLatitudeRef",
           "-GPSLongitude", "-GPSLongitudeRef", "-GPSAltitude", "-GPSAltitudeRef",
           "-DateTimeOriginal", "-SubSecTimeOriginal", "-OffsetTimeOriginal",
           "-CreateDate", "-OffsetTimeDigitized", "-r", str(photos_dir)]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    except FileNotFoundError as exc:
        raise ValueError("找不到 exiftool，请先安装。") from exc
    if result.returncode != 0:
        raise ValueError(f"ExifTool 读取失败：{result.stderr.strip()}")
    data = json.loads(result.stdout)
    if not isinstance(data, list):
        raise ValueError("ExifTool 未返回元数据列表。")
    return data


def finite_number(value):
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def parse_gps_coords(data):
    """Accept ExifTool numeric output, plus its legacy DMS representation."""
    def coordinate(value, ref):
        result = finite_number(value)
        if result is None and isinstance(value, str):
            match = re.fullmatch(r'''(\d+) deg (\d+)' ([\d.]+)" ([NSEW])''', value)
            if match:
                deg, minute, second, ref = match.groups()
                if float(minute) < 60 and float(second) < 60:
                    result = float(deg) + float(minute) / 60 + float(second) / 3600
        if result is not None and ref in ("S", "W"):
            result = -abs(result)
        return result
    lat = coordinate(data.get("GPSLatitude"), data.get("GPSLatitudeRef"))
    lon = coordinate(data.get("GPSLongitude"), data.get("GPSLongitudeRef"))
    if lat is None or lon is None or not (-90 <= lat <= 90 and -180 <= lon < 180):
        return None
    return lat, lon


def parse_datetime(data):
    value = data.get("DateTimeOriginal") or data.get("CreateDate")
    if not isinstance(value, str):
        return None
    value = re.sub(r"^(\d{4}):(\d{2}):(\d{2})", r"\1-\2-\3", value)
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
        subsec = str(data.get("SubSecTimeOriginal", ""))
        if data.get("DateTimeOriginal") and not result.microsecond and subsec.isdigit():
            result = result.replace(microsecond=int(subsec[:6].ljust(6, "0")))
        return result
    except ValueError:
        return None


def checked_timezone(hours):
    value = finite_number(hours)
    if value is None or abs(value) > 14 or not math.isclose(value * 60, round(value * 60), abs_tol=1e-7):
        raise ValueError("时区须为 -14 到 +14 之间的小时数，精确到分钟。")
    return timezone(timedelta(minutes=round(value * 60)))


def parse_timezone_offset(data):
    key = "OffsetTimeOriginal" if data.get("DateTimeOriginal") else "OffsetTimeDigitized"
    value = data.get(key)
    if value is None or value == "":
        return None
    match = re.fullmatch(r"([+-])(\d{2}):(\d{2})", str(value))
    if not match or int(match[3]) >= 60:
        raise ValueError(f"{key} 格式不合法，需使用 +08:00 这样的格式。")
    hours = (int(match[2]) + int(match[3]) / 60) * (1 if match[1] == "+" else -1)
    checked_timezone(hours)
    return hours


def photo_datetime(data, fallback=None):
    """Return an aware local datetime; missing zones cannot silently become UTC."""
    result = parse_datetime(data)
    if result is None:
        return None
    if result.tzinfo is not None:
        return result
    offset = parse_timezone_offset(data)
    if offset is None:
        offset = fallback
    if offset is None:
        raise ValueError("照片缺少时区信息，请用 --timezone 指定拍摄地时区。")
    return result.replace(tzinfo=checked_timezone(offset))


def extract_gps_photos(photos, timezone_offset=None):
    if timezone_offset is not None:
        checked_timezone(timezone_offset)
    result = []
    for photo in photos:
        coords = parse_gps_coords(photo)
        if coords is None:
            continue
        local = photo_datetime(photo, timezone_offset)
        if local is None:
            continue
        altitude = finite_number(photo.get("GPSAltitude"))
        if altitude is not None and str(photo.get("GPSAltitudeRef")) == "1":
            altitude = -abs(altitude)
        result.append({"filepath": photo.get("SourceFile", ""),
                       "filename": Path(photo.get("SourceFile", "")).name,
                       "datetime": local.astimezone(timezone.utc),
                       "local_date": local.date().isoformat(),
                       "latitude": coords[0], "longitude": coords[1], "altitude": altitude})
    return sorted(result, key=lambda p: p["datetime"])


def group_by_date(photos):
    groups = defaultdict(list)
    for photo in photos:
        groups[photo["local_date"]].append(photo)
    return dict(groups)


def generate_gpx(photos, output_path, track_name=None):
    if not photos:
        return False
    gpx = ET.Element("gpx", version="1.1", creator="PhotoTrail",
                     xmlns="http://www.topografix.com/GPX/1/1")
    trk = ET.SubElement(gpx, "trk")
    ET.SubElement(trk, "name").text = track_name or "Photo track"
    segment = None
    previous = None
    for photo in sorted(photos, key=lambda p: p["datetime"]):
        dt = photo["datetime"]
        if dt.tzinfo is None or dt.utcoffset() is None:
            raise ValueError("拒绝把未知时区的时间标记为 UTC。")
        coords = parse_gps_coords({"GPSLatitude": photo["latitude"], "GPSLongitude": photo["longitude"]})
        if coords is None:
            raise ValueError("拒绝输出不合法的经纬度。")
        if previous is None or (dt - previous).total_seconds() > 300:
            segment = ET.SubElement(trk, "trkseg")
        point = ET.SubElement(segment, "trkpt", lat=str(coords[0]), lon=str(coords[1]))
        altitude = finite_number(photo.get("altitude"))
        if altitude is not None:
            ET.SubElement(point, "ele").text = format(altitude, ".10f").rstrip("0").rstrip(".") or "0"
        ET.SubElement(point, "time").text = dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
        previous = dt
    ET.indent(gpx, space="  ")
    with Path(output_path).open("xb") as handle:
        ET.ElementTree(gpx).write(handle, encoding="utf-8", xml_declaration=True)
    return True


def extract(photos_dir, output=None, single_file=False, timezone_offset=None):
    all_photos = run_exiftool(photos_dir)
    photos = extract_gps_photos(all_photos, timezone_offset)
    if not photos:
        raise ValueError("没有同时包含有效 GPS 和拍摄时间的照片。")
    groups = {"photo_track": photos} if single_file else group_by_date(photos)
    out = Path(output or photos_dir)
    paths = [out / f"{day}_track.gpx" if day != "photo_track" else out / "photo_track.gpx" for day in groups]
    if any(p.exists() for p in paths):
        raise ValueError("目标 GPX 已存在，请选择新的输出目录。")
    out.mkdir(parents=True, exist_ok=True)
    for (day, points), path in zip(groups.items(), paths):
        generate_gpx(points, path, f"Track {day}")
    print(f"扫描 {len(all_photos)} 个文件，提取 {len(photos)} 个有效点；按拍摄当地日期分组，时间存为 UTC。")
    for path in paths:
        print(path)
    return paths


def add_extract_arguments(parser):
    parser.add_argument("photos_dir", help="源照片目录（只读）")
    parser.add_argument("-o", "--output", help="新的 GPX 输出目录")
    parser.add_argument("--single-file", action="store_true", help="输出 photo_track.gpx，仍保留长断点")
    parser.add_argument("--timezone", type=float, help="缺失时区的后备值，小时，例如 8 或 5.5")


def main(argv=None):
    parser = argparse.ArgumentParser(description="从照片提取 UTC GPX")
    add_extract_arguments(parser)
    args = parser.parse_args(argv)
    try:
        return extract(args.photos_dir, args.output, args.single_file, args.timezone)
    except (ValueError, OSError, subprocess.TimeoutExpired) as exc:
        parser.exit(1, f"错误：{exc}\n")


if __name__ == "__main__":
    main()
