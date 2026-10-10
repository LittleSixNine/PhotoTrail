import Foundation

public enum TrackAdjustmentError: Error {
    case invalidOffset, invalidPoint, missingTime
}

extension GpxTrackLog {
    /// Local east/north displacement on a mean-radius sphere (6,371,008.8 m).
    /// shortcut: limited to 100 km and latitudes below 85°, use ellipsoidal geodesics for larger/polar corrections.
    public func adjusted(seconds: Double, east: Double, north: Double) throws -> Self {
        let distance = hypot(east, north)
        guard seconds.isFinite, east.isFinite, north.isFinite, distance <= 100_000,
              abs(seconds) <= 315_576_000 else { throw TrackAdjustmentError.invalidOffset }
        guard seconds == 0 || hasRecordedTimes else { throw TrackAdjustmentError.missingTime }
        let bearing = atan2(east, north), angular = distance / 6_371_008.8
        let tracks = try tracks.map { track in
            var result = track
            result.segments = try track.segments.map { segment in
                var result = segment
                result.points = try segment.points.map { point in
                    guard point.lat.isFinite, point.lon.isFinite, abs(point.lat) <= 90, abs(point.lon) <= 180,
                          !point.hasRecordedTime || point.timeFromEpoch.isFinite else { throw TrackAdjustmentError.invalidPoint }
                    var lat = point.lat, lon = point.lon
                    if distance > 0 {
                        guard abs(lat) < 85 else { throw TrackAdjustmentError.invalidPoint }
                        let latitude = lat * .pi / 180, longitude = lon * .pi / 180
                        let moved = asin(sin(latitude) * cos(angular) + cos(latitude) * sin(angular) * cos(bearing))
                        lat = moved * 180 / .pi
                        lon = (longitude + atan2(sin(bearing) * sin(angular) * cos(latitude),
                                                cos(angular) - sin(latitude) * sin(moved))) * 180 / .pi
                        lon = (lon + 540).truncatingRemainder(dividingBy: 360) - 180
                        guard abs(lat) < 85 else { throw TrackAdjustmentError.invalidPoint }
                    }
                    let time = point.hasRecordedTime ? point.timeFromEpoch + seconds : point.timeFromEpoch
                    guard !point.hasRecordedTime || (time >= -62_135_596_800 && time < 253_402_300_800) else {
                        throw TrackAdjustmentError.invalidPoint
                    }
                    return Point(hasRecordedTime: point.hasRecordedTime, lat: lat, lon: lon,
                                 ele: point.ele, timeFromEpoch: time)
                }
                return result
            }
            return result
        }
        return Self(sourceURL: sourceURL, tracks: tracks)
    }

    public func gpxData() throws -> Data {
        _ = try adjusted(seconds: 0, east: 0, north: 0)
        let formatter = ISO8601DateFormatter()
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"PhotoTrail\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        for track in tracks {
            xml += "<trk>\n"
            for segment in track.segments {
                xml += "<trkseg>\n"
                for point in segment.points {
                    xml += "<trkpt lat=\"\(point.lat)\" lon=\"\(point.lon)\">"
                    if let elevation = point.ele {
                        guard elevation.isFinite else { throw TrackAdjustmentError.invalidPoint }
                        xml += "<ele>\(elevation)</ele>"
                    }
                    if point.hasRecordedTime {
                        var whole = floor(point.timeFromEpoch)
                        var nanos = Int(((point.timeFromEpoch - whole) * 1_000_000_000).rounded())
                        if nanos == 1_000_000_000 { whole += 1; nanos = 0 }
                        let date = formatter.string(from: Date(timeIntervalSince1970: whole))
                        xml += "<time>" + date.dropLast() + String(format: ".%09dZ", nanos) + "</time>"
                    }
                    xml += "</trkpt>\n"
                }
                xml += "</trkseg>\n"
            }
            xml += "</trk>\n"
        }
        return Data((xml + "</gpx>\n").utf8)
    }
}
