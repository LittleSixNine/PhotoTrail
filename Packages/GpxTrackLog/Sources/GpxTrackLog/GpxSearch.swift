import CoreLocation
import Foundation

extension GpxTrackLog {

    public enum MatchMethod: String, Sendable {
        case recorded
        case linear
    }

    public struct MatchResult: Sendable {
        public let coordinate: CLLocationCoordinate2D
        public let elevation: Double?
        public let method: MatchMethod
        public let timeDelta: TimeInterval
        public let reason: String
    }

    public enum MatchOutcome: Sendable {
        case matched(MatchResult)
        case ambiguous(String)
        case unmatched(String)
    }

    /// Conservatively locate a timestamp without crossing segment boundaries or
    /// extrapolating beyond the recorded coverage. Interpolation is only used
    /// between two ordered, timed points whose gap is within `maximumGap`.
    public func match(imageTime: TimeInterval,
                      maximumGap: TimeInterval = 120 * 60) -> MatchOutcome {
        MatchIndex(self).match(imageTime: imageTime, maximumGap: maximumGap)
    }

    /// Split at non-increasing timestamps. Overlapping runs are queried independently so
    /// repeated times and conflicting locations retain their original order and ambiguity.
    public struct MatchIndex: Sendable {
        private let runs: [[Point]]
        private let invalidTimeOrder: Bool

        public init(_ log: GpxTrackLog) {
            var runs: [[Point]] = []
            var invalid = false
            for segment in log.tracks.flatMap(\.segments) {
                var run: [Point] = []
                for point in segment.points where point.hasRecordedTime && point.timeFromEpoch.isFinite
                    && point.lat.isFinite && point.lon.isFinite && abs(point.lat) <= 90 && abs(point.lon) <= 180 {
                    if let last = run.last, last.timeFromEpoch >= point.timeFromEpoch {
                        invalid = true
                        runs.append(run)
                        run = []
                    }
                    run.append(point)
                }
                if !run.isEmpty { runs.append(run) }
            }
            self.runs = runs
            invalidTimeOrder = invalid
        }

        public func match(imageTime: TimeInterval, maximumGap: TimeInterval) -> MatchOutcome {
            guard imageTime.isFinite, maximumGap > 0, maximumGap.isFinite else {
                return .unmatched("照片时间或匹配间隔无效。")
            }

            var exact = [MatchResult]()
            var interpolated = [MatchResult]()
            for points in runs {
                guard let first = points.first, let last = points.last,
                      first.timeFromEpoch <= imageTime, imageTime <= last.timeFromEpoch else { continue }
                var low = 0, high = points.count
                while low < high {
                    let mid = low + (high - low) / 2
                    if points[mid].timeFromEpoch < imageTime { low = mid + 1 } else { high = mid }
                }
                let point = points[low]
                if point.timeFromEpoch == imageTime {
                    exact.append(MatchResult(coordinate: .init(latitude: point.lat, longitude: point.lon),
                        elevation: point.ele, method: .recorded, timeDelta: 0, reason: "时间与原始轨迹点一致。"))
                } else {
                    let before = points[low - 1], after = point
                    let duration = after.timeFromEpoch - before.timeFromEpoch
                    guard duration <= maximumGap else { continue }
                    let fraction = (imageTime - before.timeFromEpoch) / duration
                    let longitudeDelta = (after.lon - before.lon + 540)
                        .truncatingRemainder(dividingBy: 360) - 180
                    let longitude = (before.lon + longitudeDelta * fraction + 540)
                        .truncatingRemainder(dividingBy: 360) - 180
                    let elevation = before.ele.flatMap { first in
                        after.ele.map { first + ($0 - first) * fraction }
                    }
                    interpolated.append(MatchResult(
                        coordinate: .init(latitude: before.lat + (after.lat - before.lat) * fraction,
                                          longitude: longitude),
                        elevation: elevation, method: .linear,
                        timeDelta: min(imageTime - before.timeFromEpoch,
                                       after.timeFromEpoch - imageTime),
                        reason: "在同一轨迹段的相邻记录点之间按拍摄时间线性插值。"))
                }
            }

            let candidates = exact.isEmpty ? interpolated : exact
            guard let first = candidates.first else {
                return .unmatched(invalidTimeOrder
                    ? "轨迹时间倒退或重复冲突，未自动匹配。"
                    : "拍摄时间不在可安全插值的轨迹区间内。")
            }
            let origin = CLLocation(latitude: first.coordinate.latitude,
                                    longitude: first.coordinate.longitude)
            guard candidates.dropFirst().allSatisfy({ candidate in
                origin.distance(from: CLLocation(latitude: candidate.coordinate.latitude,
                                                 longitude: candidate.coordinate.longitude)) <= 1
            }) else {
                return .ambiguous("同一拍摄时间对应多个不同位置，需选择轨迹来源。")
            }
            return .matched(first)
        }

    }

    /// Search for the last point in the track log with a timestamp <= the
    /// timestamp of a given image.
    ///
    /// - Parameter imageTime:    the time from epoch of an image whose
    ///                           coords are desired
    /// - Parameter extendedTime: number of minutes that a tracklog entry can
    ///                           vary to match the image timestamp.
    ///                           Default is 2 hours (120 minutes)
    ///

    public func search(imageTime: TimeInterval,
                       extendedTime: Double = 120.0)
    -> (CLLocationCoordinate2D, Double?)? {
        let seconds = extendedTime == 0 ? 60 : extendedTime * 60
        guard case .matched(let result) = match(imageTime: imageTime,
                                                maximumGap: seconds) else { return nil }
        return (result.coordinate, result.elevation)
    }
}
