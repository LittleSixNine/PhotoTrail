"""Local, conservative trajectory analysis. No network calls or photo writes."""
from bisect import bisect_left
from collections import Counter
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import math
import json
from pathlib import Path
from statistics import median
import xml.etree.ElementTree as ET

from extract_gpx import finite_number, parse_gps_coords

EARTH_RADIUS = 6371008.8


@dataclass(frozen=True)
class Policy:
    infer_after: float = 15.0
    max_infer_gap: float = 60.0
    break_after: float = 300.0
    dense_distance: float = 30.0
    max_speed: float = 3.0
    accuracy_allowance: float = 10.0

    def __post_init__(self):
        if any(finite_number(v) is None or v <= 0 for v in asdict(self).values()):
            raise ValueError("策略参数必须为正的有限数。")
        if not self.infer_after <= self.max_infer_gap <= self.break_after:
            raise ValueError("需满足：推理阈值 ≤ 自动推理上限 ≤ 断点上限。")


@dataclass(frozen=True)
class Point:
    time: datetime
    lat: float
    lon: float
    segment: int = 0

    def json(self):
        return {"time": iso(self.time), "timestamp": self.time.timestamp(),
                "latitude": self.lat, "longitude": self.lon, "segment": self.segment}


def iso(value):
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_time(value):
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (ValueError, AttributeError) as exc:
        raise ValueError("时间需使用带时区的 ISO 8601 格式，例如 2026-01-01T10:00:00+08:00。") from exc
    if dt.tzinfo is None or dt.utcoffset() is None:
        raise ValueError("时间缺少时区，不能可靠匹配。")
    return dt.astimezone(timezone.utc)


def read_gpx(path):
    path = Path(path)
    if path.stat().st_size > 50_000_000:
        raise ValueError("GPX 超过 50 MB，请先按连续行程分割。")
    raw = path.read_bytes()
    if b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
        raise ValueError("不接受包含 DTD 或实体声明的 GPX。")
    try:
        root = ET.fromstring(raw)
    except ET.ParseError as exc:
        raise ValueError(f"GPX XML 不合法：{exc}") from exc
    local = lambda e: e.tag.rsplit("}", 1)[-1]
    if local(root) != "gpx":
        raise ValueError("输入不是 GPX。")
    points = []
    for segment_id, segment in enumerate(e for e in root.iter() if local(e) == "trkseg"):
        for element in segment:
            if local(element) != "trkpt":
                continue
            coords = parse_gps_coords({"GPSLatitude": element.get("lat"), "GPSLongitude": element.get("lon")})
            time = next((e.text for e in element if local(e) == "time"), None)
            if coords is None or time is None:
                raise ValueError("轨迹点缺少有效坐标或时间；不能静默删除后跨越该点插值。")
            point = Point(parse_time(time), *coords, segment_id)
            if points:
                last = points[-1]
                if point.time < last.time:
                    raise ValueError("GPX 时间倒退或轨迹段重叠，请按连续行程分别处理。")
                if point.time == last.time:
                    if (point.lat, point.lon) != (last.lat, last.lon):
                        raise ValueError("同一时刻存在不同坐标，需先解决冲突。")
                    if point.segment == last.segment:
                        continue
            points.append(point)
    if not points:
        raise ValueError("GPX 中没有带时间的 trkpt 轨迹点。")
    return points


def distance(a, b):
    lat1, lat2 = math.radians(a.lat), math.radians(b.lat)
    dlat, dlon = lat2 - lat1, math.radians(b.lon - a.lon)
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS * math.asin(math.sqrt(min(1.0, max(0.0, h))))


def project(point, origin):
    dlon = (point.lon - origin.lon + 180) % 360 - 180
    return (EARTH_RADIUS * math.radians(dlon) * math.cos(math.radians(origin.lat)),
            EARTH_RADIUS * math.radians(point.lat - origin.lat))


def unproject(xy, origin):
    lat = origin.lat + math.degrees(xy[1] / EARTH_RADIUS)
    lon = origin.lon + math.degrees(xy[0] / (EARTH_RADIUS * math.cos(math.radians(origin.lat))))
    return lat, (lon + 180) % 360 - 180


def lerp_coords(a, b, fraction):
    lat = a[0] + (b[0] - a[0]) * fraction
    lon = a[1] + ((b[1] - a[1] + 180) % 360 - 180) * fraction
    return lat, (lon + 180) % 360 - 180


def stationary_intervals(points, policy):
    """Require >=3 nearby observations and >=30 s, with no sparse gaps."""
    stops = {}
    start = 0
    while start < len(points):
        end = start
        while end + 1 < len(points):
            following = points[end + 1]
            dt = (following.time - points[end].time).total_seconds()
            if (following.segment != points[start].segment or dt > policy.infer_after
                    or distance(points[start], following) > 5):
                break
            end += 1
        if end - start >= 2 and (points[end].time - points[start].time).total_seconds() >= 30:
            # Use a middle observation instead of inventing a point outside the cluster.
            center = points[(start + end) // 2]
            for i in range(start, end):
                stops[i] = (center.lat, center.lon)
        start = end + 1
    return stops


def curve_samples(points, index, rows, policy):
    """Four-point time-aware Hermite curve, with progress and deviation bounds."""
    if index < 1 or index + 2 >= len(points):
        return None, "前后不足四个记录点，保留线性候选。"
    if rows[index - 1]["decision"] not in ("dense", "infer") or rows[index + 1]["decision"] not in ("dense", "infer"):
        return None, "相邻区间存在断点、停留或异常，保留线性候选。"
    a, b, c, d = points[index - 1:index + 3]
    if len({p.segment for p in (a, b, c, d)}) != 1 or abs(b.lat) > 85:
        return None, "轨迹边界或投影范围不支持曲线，保留线性候选。"
    h0, h1, h2 = [(q.time - p.time).total_seconds() for p, q in ((a, b), (b, c), (c, d))]
    if min(h0, h1, h2) <= 0:
        return None, "相邻记录时间不唯一，保留线性候选。"
    aa, cc, dd = project(a, b), project(c, b), project(d, b)
    length = math.hypot(*cc)
    if length < 5:
        return None, "位移过小，曲线缺乏方向依据。"
    prev = [-v / h0 for v in aa]
    current = [v / h1 for v in cc]
    after = [(dd[k] - cc[k]) / h2 for k in range(2)]
    v0 = [(h1 * prev[k] + h0 * current[k]) / (h0 + h1) for k in range(2)]
    v1 = [(h2 * current[k] + h1 * after[k]) / (h1 + h2) for k in range(2)]
    for velocity in (v0, v1):
        if sum(velocity[k] * cc[k] for k in range(2)) <= 0:
            return None, "方向反转或急转弯，曲线可能过冲。"
        speed = math.hypot(*velocity)
        limit = min(2 * length / h1, policy.max_speed)
        if speed > limit:
            velocity[:] = [v * limit / speed for v in velocity]
    samples = []
    last_xy = None
    previous_progress = -1e-9
    for j in range(21):
        u = j / 20
        xy = [(u**3 - 2*u*u + u) * h1 * v0[k]
              + (-2*u**3 + 3*u*u) * cc[k]
              + (u**3 - u*u) * h1 * v1[k] for k in range(2)]
        progress = sum(xy[k] * cc[k] for k in range(2)) / length**2
        deviation = abs(xy[0] * cc[1] - xy[1] * cc[0]) / length
        if progress < previous_progress - 1e-8 or not -1e-8 <= progress <= 1 + 1e-8 or deviation > min(10, length * .25):
            return None, "曲线偏离或过冲超过限制，保留线性候选。"
        if last_xy is not None and math.dist(xy, last_xy) / (h1 / 20) > policy.max_speed + 2 * policy.accuracy_allowance / h1:
            return None, "曲线速度不合理，保留线性候选。"
        lat, lon = unproject(xy, b)
        samples.append([b.time.timestamp() + u * h1, lat, lon])
        previous_progress, last_xy = progress, xy
    return samples, "仅依据四个相邻观测点和真实时间的局部曲线；尚无道路证据。"


def analyze(points, policy=None):
    policy = policy or Policy()
    if not points:
        raise ValueError("没有轨迹点。")
    stops = stationary_intervals(points, policy)
    rows = []
    positive_gaps = [(b.time-a.time).total_seconds() for a, b in zip(points, points[1:])
                     if a.segment == b.segment and 0 < (b.time-a.time).total_seconds() <= policy.break_after]
    for i, (a, b) in enumerate(zip(points, points[1:])):
        dt, meters = (b.time - a.time).total_seconds(), distance(a, b)
        nearby = [(points[j + 1].time - points[j].time).total_seconds()
                  for j in range(max(0, i-3), min(len(points)-1, i+4)) if j != i
                  and points[j].segment == a.segment == points[j+1].segment
                  and 0 < (points[j+1].time-points[j].time).total_seconds() <= policy.break_after]
        baseline = median(nearby) if nearby else None
        samples = [[a.time.timestamp(), a.lat, a.lon], [b.time.timestamp(), b.lat, b.lon]]
        if a.segment != b.segment:
            decision, reason = "gap", "GPX 原有轨迹段边界，不跨段补线。"
        elif dt <= 0:
            raise ValueError("段内轨迹时间必须严格递增。")
        elif dt > policy.break_after:
            decision, reason = "gap", "超过断点上限，不自动补线。"
        elif max(0, meters - 2 * policy.accuracy_allowance) / dt > policy.max_speed:
            decision, reason = "jump", "位移速度不符合当前步行设置；可能是漂移或交通方式变化。"
        elif i in stops:
            decision, reason = "stationary", "至少三个密集观测点形成持续 30 秒以上的 5 米范围点簇；推测停留。"
        elif dt <= policy.infer_after:
            if meters <= policy.dense_distance:
                decision, reason = "dense", "时间与距离满足密集记录条件，使用原始连线，不额外推理。"
            else:
                decision, reason = "review", "时间间隔虽短，距离超过密集记录上限；不自动补线。"
        elif dt <= policy.max_infer_gap:
            decision, reason = "infer", "超过推理阈值，且处于自动候选区间。"
        else:
            decision, reason = "review", "超过自动推理上限；需要道路或其他额外证据。"
        if baseline is not None and dt > 3 * baseline:
            reason += " 此间隔大于附近采样中位数的三倍。"
        rows.append({"index": i, "start": iso(a.time), "end": iso(b.time),
                     "seconds": dt, "meters": round(meters, 3),
                     "nearby_median_seconds": baseline, "decision": decision, "reason": reason,
                     "method": "linear", "samples": samples})
    for i, row in enumerate(rows):
        if row["decision"] in ("gap", "jump", "review"):
            row["method"] = "unresolved"
            row["samples"] = []
        elif row["decision"] == "stationary":
            row["method"] = "stationary"
            row["samples"] = [[points[k].time.timestamp(), *stops[i]] for k in (i, i+1)]
        elif row["decision"] == "infer":
            samples, reason = curve_samples(points, i, rows, policy)
            row["reason"] += " " + reason
            row["method"] = "curve" if samples else "linear_candidate"
            if samples:
                row["samples"] = samples
    return {"schema_version": 1, "coordinate_system": "WGS84", "policy": asdict(policy),
            "anchors": [p.json() for p in points], "intervals": rows,
            "summary": {"points": len(points), "intervals": len(rows),
                        "median_interval_seconds": median(positive_gaps) if positive_gaps else None,
                        "decisions": dict(Counter(r["decision"] for r in rows)),
                        "methods": dict(Counter(r["method"] for r in rows))},
            "limitations": ["15 秒等阈值是可调的初始策略，尚未经过真实行程标定。",
                            "密集点仍可能漂移；曲线是估算，不能恢复隐藏停留或证明实际路线。",
                            "此版本不调用地图 API，不包含道路匹配结果。"]}


class Locator:
    """Reuse a sorted index when locating many photographs."""
    def __init__(self, report):
        self.report = report
        self.times = [p["timestamp"] for p in report["anchors"]]

    def locate(self, when):
        dt = parse_time(when) if isinstance(when, str) else when
        if dt.tzinfo is None or dt.utcoffset() is None:
            raise ValueError("定位时间缺少时区。")
        timestamp = dt.timestamp()
        i = bisect_left(self.times, timestamp)
        result = {"time": iso(dt), "status": "unresolved", "latitude": None, "longitude": None,
                  "method": "none", "requires_review": True}
        if i < len(self.times) and self.times[i] == timestamp:
            p = self.report["anchors"][i]
            suspect = any(self.report["intervals"][j]["decision"] == "jump"
                          for j in (i-1, i) if 0 <= j < len(self.report["intervals"]))
            return {**result, "status": "recorded", "latitude": p["latitude"], "longitude": p["longitude"],
                    "method": "recorded", "requires_review": suspect,
                    "reason": "原始观测点；邻近存在异常跳点。" if suspect else "时间与原始观测点一致。"}
        if i == 0 or i == len(self.times):
            return {**result, "reason": "时间在轨迹覆盖范围之外，不外推。"}
        row = self.report["intervals"][i-1]
        samples = row["samples"]
        if not samples:
            return {**result, "interval": i-1, "reason": row["reason"]}
        j = min(len(samples)-1, max(1, bisect_left([s[0] for s in samples], timestamp)))
        a, b = samples[j-1], samples[j]
        fraction = (timestamp-a[0]) / (b[0]-a[0])
        lat, lon = lerp_coords(a[1:], b[1:], fraction)
        return {**result, "status": "estimated", "latitude": lat, "longitude": lon,
                "method": row["method"], "requires_review": row["decision"] == "infer",
                "interval": i-1, "reason": row["reason"]}


def prepare_road_requests(points, report):
    """Build reviewable Baidu form payloads, never send them or include a key.

    Dense points are context only. Windows cannot cross unresolved intervals.
    Provider reference: https://lbsyun.baidu.com/docs/webapi?title=rectify/guide/trackrectify-base
    """
    rows = report["intervals"]
    windows = []
    for i, row in enumerate(rows):
        if row["decision"] != "infer":
            continue
        left, right = i, i + 1
        for _ in range(3):
            if left and rows[left-1]["decision"] in ("dense", "infer", "stationary"):
                left -= 1
            else:
                break
        for _ in range(3):
            if right < len(rows) and rows[right]["decision"] in ("dense", "infer", "stationary"):
                right += 1
            else:
                break
        if windows and left <= windows[-1][1]:
            windows[-1][1] = max(right, windows[-1][1])
        else:
            windows.append([left, right])
    requests, blocked = [], []
    for left, right in windows:
        while left < right:
            end = min(left + 1999, right)
            candidates = [i for i in range(left, end) if rows[i]["decision"] == "infer"]
            if candidates:
                selected = points[left:end+1]
                stamps = [int(p.time.timestamp()) for p in selected]
                if len(stamps) != len(set(stamps)):
                    blocked.append({"start_index": left, "end_index": end,
                                    "reason": "秒级时间戳重复，需先决定如何处理亚秒记录。"})
                elif sum(distance(a,b) for a,b in zip(selected,selected[1:])) > 500000:
                    blocked.append({"start_index": left, "end_index": end,
                                    "reason": "超过服务单次 500 公里限制，请重新分段。"})
                else:
                    point_list = [{"latitude": p.lat, "longitude": p.lon, "loc_time": t,
                                   "coord_type_input": "wgs84"} for p,t in zip(selected,stamps)]
                    requests.append({"start_index": left, "end_index": end,
                                     "candidate_intervals": candidates, "point_count": len(point_list),
                                     "form": {"point_list": json.dumps(point_list, separators=(",", ":")),
                                              "rectify_option": "need_mapmatch:1|transport_mode:walking|denoise_grade:1|vacuate_grade:0",
                                              "supplement_mode": "no_supplement", "coord_type_output": "gcj02"}})
            if end == right:
                break
            left = end - 3
    return {"provider": "baidu", "endpoint": "https://api.map.baidu.com/rectify/v1/track",
            "method": "POST", "encoding": "application/x-www-form-urlencoded",
            "sent": False, "requires_api_key": True,
            "notice": "仅生成待审阅请求。真实上传需授权；国内返回 GCJ-02，尚不能直接写入 WGS84 照片。",
            "requests": requests, "blocked_windows": blocked}
