import Coords
import CoreLocation
import Foundation
import GpxTrackLog
import ImageData
import UDF

@MainActor
enum LocationHelper {

    static func canFillRegion(_ image: ImageData) -> Bool {
        guard image.updatable, image.creatorDraft == nil, image.metadata.location != nil,
              image.metadata.canDisplayAsWGS84 else { return false }
        switch image.metadata.source {
        case .image, .xmp: break
        case .photos, .copy: return false
        }
        return [image.metadata.city, image.metadata.state, image.metadata.sublocation,
                image.metadata.country, image.metadata.countryCode].contains { $0?.isEmpty != false }
    }

    static func fillRegions(_ store: Store<PhotoTrailState, PhotoTrailEvent>, workspace: LocationWorkspace) async {
        guard !store.saveInProgress, !store.importProgress.isActive else { return }
        let images = store.imageData.filter { store.selection.contains($0.id) }
        let provider = UserDefaults.standard.string(forKey: "PhotoTrailMapProvider") ?? "amap"
        var addresses: [ImageData.ID: Place] = [:]
        var failed = 0
        for image in images where canFillRegion(image) {
            guard let point = image.metadata.location else { continue }
            do {
                addresses[image.id] = try await workspace.address(at:
                    MapCoordinate(latitude: point.latitude, longitude: point.longitude), provider: provider)
            } catch { failed += 1 }
            if Task.isCancelled { return }
        }
        guard !store.saveInProgress, !store.importProgress.isActive else { return }
        let before = Dictionary(uniqueKeysWithValues: images.map { ($0.id, store[$0.id].metadata) })
        store.send(.missingAddressesFilled(addresses), description: L10n.text("补齐地区信息"))
        let changed = images.filter { before[$0.id] != store[$0.id].metadata }.count
        workspace.status = L10n.text("地区信息已暂存：%1$@ 张；查询失败：%2$@ 张；未补齐：%3$@ 张。请写入所有元数据。",
                                     changed, failed, images.count - changed - failed)
    }

    static func photoIDs(in images: [ImageData], timeZone: TimeZone,
                         tracks: [GpxTrackLog]) -> Set<ImageData.ID> {
        let ranges = tracks.flatMap(\.tracks).flatMap(\.segments).compactMap { segment -> ClosedRange<TimeInterval>? in
            let times = segment.points.filter {
                $0.hasRecordedTime && $0.timeFromEpoch.isFinite
                    && $0.lat.isFinite && $0.lon.isFinite
                    && abs($0.lat) <= 90 && abs($0.lon) <= 180
            }
                .map(\.timeFromEpoch)
            guard let first = times.min(), let last = times.max() else { return nil }
            return first...last
        }
        return Set(images.compactMap { image in
            guard image.updatable, let date = image.metadata.parsedDate(timeZone: timeZone),
                  ranges.contains(where: { $0.contains(date.timeIntervalSince1970) }) else { return nil }
            return image.id
        })
    }

    // struct to hold id and timestamp of an image to look location

    struct LocationById: Equatable, Identifiable {
        enum Status: String, Equatable, Sendable {
            case matched
            case ambiguous
            case unmatched
            case missingTime
            case alreadyLocated
        }

        var listStatus: String {
            switch status {
            case .matched: L10n.text("匹配成功")
            case .ambiguous: L10n.text("需检查")
            case .unmatched: L10n.text("未匹配")
            case .missingTime: L10n.text("缺少时间")
            case .alreadyLocated: L10n.text("跳过已有定位")
            }
        }

        var id: ImageData.ID
        var timestamp: TimeInterval
        var coords: Coords?
        var elevation: Double?
        var status: Status = .matched
        var method: GpxTrackLog.MatchMethod?
        var sourceURL: URL?
        var reason = ""
    }

    @MainActor
    @discardableResult
    static func locationFromTrack(_ store: Store<PhotoTrailState, PhotoTrailEvent>,
                                  extendedTime: Double,
                                  overwriteExisting: Bool = false,
                                  tracks: [GpxTrackLog]? = nil) -> Task<Void, Never> {
        var locations: [LocationById] = []
        let timeZone = store.timeZone

        for id in store.selection {
            let metadata = store[id].metadata
            if metadata.location != nil && !overwriteExisting {
                locations.append(LocationById(id: id, timestamp: 0, coords: nil, elevation: nil,
                                              status: .alreadyLocated,
                                              reason: L10n.text("照片已有定位，默认不覆盖。")))
            } else if let date = metadata.parsedDate(timeZone: timeZone) {
                locations.append(LocationById(id: id, timestamp: date.timeIntervalSince1970,
                                              coords: nil, elevation: nil))
            } else {
                locations.append(LocationById(id: id, timestamp: 0, coords: nil, elevation: nil,
                                              status: .missingTime,
                                              reason: L10n.text("拍摄时间缺失或格式错误。")))
            }
        }
        let frozenTracks = store.gpxTracks
        let matchingTracks = tracks ?? frozenTracks
        let task = Task {
            let updatedLocations = await Self.locations(for: locations,
                                                        extendedTime: extendedTime,
                                                        tracks: matchingTracks)
            guard store.gpxTracks == frozenTracks else { return }
            store.send(.locationFromTrack(updatedLocations),
                       undoable: false)
        }
        return task
    }

    // look up the location for all the LocationById entries passed to
    // the function. The entries are updated when a location within
    // timestamp...timestamp+extendedTime is found.

    static nonisolated func locations(for locations: [LocationById],
                                      extendedTime: Double,
                                      tracks: [GpxTrackLog]) async -> [LocationById] {
        func findLocation(_ ix: Int) -> (Int, LocationById) {
            let input = locations[ix]
            guard input.status == .matched else { return (ix, input) }
            let maximumGap = (extendedTime == 0 ? 1 : extendedTime) * 60
            var matches: [(GpxTrackLog.MatchResult, URL)] = []
            var reasons = [String]()
            var ambiguous = false
            for track in tracks {
                switch track.match(imageTime: input.timestamp, maximumGap: maximumGap) {
                case .matched(let result): matches.append((result, track.sourceURL))
                case .ambiguous(let reason):
                    ambiguous = true
                    reasons.append(L10n.text(reason))
                case .unmatched(let reason): reasons.append(L10n.text(reason))
                }
            }
            guard !ambiguous, let first = matches.first else {
                var result = input
                result.status = ambiguous ? .ambiguous : .unmatched
                result.reason = reasons.first ?? L10n.text("没有可用轨迹。")
                return (ix, result)
            }
            let origin = CLLocation(latitude: first.0.coordinate.latitude,
                                    longitude: first.0.coordinate.longitude)
            guard matches.dropFirst().allSatisfy({ candidate in
                origin.distance(from: CLLocation(latitude: candidate.0.coordinate.latitude,
                                                 longitude: candidate.0.coordinate.longitude)) <= 1
            }) else {
                var result = input
                result.status = .ambiguous
                result.reason = L10n.text("多个轨迹在该时间对应不同位置，需选择轨迹来源。")
                return (ix, result)
            }
            var result = input
            result.coords = Coords(latitude: first.0.coordinate.latitude,
                                   longitude: first.0.coordinate.longitude)
            result.elevation = first.0.elevation
            result.method = first.0.method
            result.sourceURL = first.1
            result.reason = L10n.text(first.0.reason)
            return (ix, result)
        }

        var ordered = Array<LocationById?>(repeating: nil, count: locations.count)
        await withTaskGroup { group in
            var limit = min(locations.count, PhotoTrailApp.maxConcurrentTasks)
            var index = locations.startIndex
            for _ in 0..<limit {
                let ix = index
                index = locations.index(after: index)
                group.addTask { return findLocation(ix) }
            }

            for await (resultIndex, result) in group {
                if limit < locations.count {
                    limit += 1
                    let ix = index
                    index = locations.index(after: index)
                    group.addTask { return findLocation(ix) }
                }

                ordered[resultIndex] = result
            }
        }
        return ordered.compactMap { $0 }
    }
}
