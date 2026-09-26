import Coords
import CryptoKit
import Foundation
import GpxTrackLog
import Observation

enum TrackOrigin: String, Codable {
    case photos
}

struct TrackRecord: Codable, Identifiable, Equatable {
    var log: GpxTrackLog
    var bookmark: Data?
    var converted: [[MapCoordinate]]?
    var convertedAt: Date?
    var convertedSource: String?
    var origin: TrackOrigin? = nil
    var cacheIsCurrent: Bool { converted != nil && convertedSource == fingerprint }
    var sourceUnavailable = false
    var id: String { log.sourceURL.path }
    var name: String { log.sourceURL.lastPathComponent }
    var generatedFromPhotos: Bool { origin == .photos }
    var points: [GpxTrackLog.Point] { log.tracks.flatMap(\.segments).flatMap(\.points) }
    var segments: [[MapCoordinate]] {
        log.tracks.flatMap(\.segments).map { $0.points.map {
            MapCoordinate(latitude: $0.lat, longitude: $0.lon)
        } }.filter { $0.count >= 2 }
    }
    // Coordinate order and segment boundaries matter; filename and timestamps do not.
    var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(segments)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    var timeRange: String {
        let times = points.filter(\.hasRecordedTime).map(\.timeFromEpoch).filter(\.isFinite)
        guard let first = times.min(), let last = times.max() else { return L10n.text("无记录时间") }
        let start = Date(timeIntervalSince1970: first), end = Date(timeIntervalSince1970: last)
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("yyyyMMddHHmm")
        let startText = formatter.string(from: start)
        if Calendar.current.isDate(start, inSameDayAs: end) { formatter.setLocalizedDateFormatFromTemplate("HHmm") }
        return "\(startText)–\(formatter.string(from: end))"
    }
    static func valid(_ converted: [[MapCoordinate]], for source: [[MapCoordinate]]) -> Bool {
        converted.map(\.count) == source.map(\.count) && converted.flatMap { $0 }.allSatisfy(\.isValid)
    }
}

enum TrackConversionState: Equatable {
    case loading(Int, Int)
    case failed(String)
}

struct TrackDisplay: Codable, Equatable {
    let id: String
    let version: String
    let segments: [[MapCoordinate]]
}

@MainActor @Observable
final class TrackLibrary {
    private(set) var records: [TrackRecord] = []
    private(set) var activeIDs: [String] = []
    var activeRecords: [TrackRecord] { activeIDs.compactMap { record($0) } }
    var nextRequestID: String? { requests.min { $0.value < $1.value }?.key }
    private(set) var visible: Set<String> = []
    private(set) var selected: String?
    private(set) var states: [String: TrackConversionState] = [:]
    private(set) var requests: [String: Int] = [:]
    private(set) var revision = 0
    private(set) var fitRevision = 0
    var storageError: String?
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var unreadable = false
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var storeIDs: Set<String> = []
    @ObservationIgnored private var scopedURLs: [URL] = []
    @ObservationIgnored private var photoGeneratedURLs: Set<String> = []

    private struct Archive: Codable {
        var version = 1
        var records: [TrackRecord]
    }

    init(url: URL? = nil) {
        let current = url ?? URL.applicationSupportDirectory
            .appendingPathComponent("PhotoTrail/Tracks/cache-v1.json")
        if url == nil {
            PhotoTrailMigration.file(at: current, legacyURL: URL.applicationSupportDirectory
                .appendingPathComponent("GeoTagCN/Tracks/cache-v1.json"))
        }
        self.url = current
    }

    func record(_ id: String) -> TrackRecord? { records.first { $0.id == id } }

    func markPhotoGenerated(_ url: URL) {
        photoGeneratedURLs.insert(url.standardizedFileURL.path)
    }

    // Called once by the owning window. Cache and source files are never read on visibility toggles.
    func restore() -> [GpxTrackLog] {
        guard !loaded else { return [] }
        loaded = true
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
            guard archive.version == 1, Set(archive.records.map(\.id)).count == archive.records.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            records = try archive.records.map { saved in
                var record = saved
                guard record.log.sourceURL.isFileURL,
                      record.points.allSatisfy({ $0.lat.isFinite && $0.lon.isFinite }) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                if let converted = record.converted, (!TrackRecord.valid(converted, for: record.segments) || !record.cacheIsCurrent) {
                    record.converted = nil; record.convertedAt = nil
                }
                do {
                    var source = record.log.sourceURL
                    if let bookmark = record.bookmark {
                        var stale = false
                        source = try URL(resolvingBookmarkData: bookmark,
                            options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
                    }
                    if source.startAccessingSecurityScopedResource() { scopedURLs.append(source) }
                    let log = try GpxTrackLog(contentsOf: source)
                    let oldFingerprint = record.fingerprint
                    record.log = log
                    record.bookmark = bookmark(for: source)
                    record.sourceUnavailable = false
                    if record.fingerprint != oldFingerprint {
                        record.converted = nil; record.convertedAt = nil
                    }
                } catch { record.sourceUnavailable = true }
                return record
            }
            let logs = records.filter { !$0.sourceUnavailable }.map(\.log)
            // History is restored independently of this window.
            revision += 1
            return logs
        } catch {
            unreadable = true
            storageError = L10n.text("轨迹缓存无法读取，原文件已保留。可重新导入轨迹；本次转换结果仅在内存中保留。")
            return []
        }
    }

    func synchronize(_ logs: [GpxTrackLog], amap: Bool = false) {
        let ids = Set(logs.map { $0.sourceURL.path })
        for id in storeIDs.subtracting(ids) { remove(id) }
        for log in logs {
            let id = log.sourceURL.path
            var changed = false
            if let index = records.firstIndex(where: { $0.id == id }) {
                if records[index].log != log || records[index].sourceUnavailable {
                    let oldFingerprint = records[index].fingerprint
                    records[index].log = log
                    records[index].sourceUnavailable = false
                    records[index].bookmark = bookmark(for: log.sourceURL)
                    changed = records[index].fingerprint != oldFingerprint
                    if changed {
                        records[index].converted = nil; records[index].convertedAt = nil
                        cancel(id)
                    }
                }
            } else {
                let generated = photoGeneratedURLs.remove(id) != nil || Self.isPhotoGenerated(log.sourceURL)
                records.append(TrackRecord(log: log, bookmark: bookmark(for: log.sourceURL),
                                           origin: generated ? .photos : nil))
            }
            if !activeIDs.contains(id) {
                activeIDs.append(id)
                setVisible(id, true, amap: amap)
                if selected == nil { selected = id; fitRevision += 1 }
            } else if changed && visible.contains(id) {
                setVisible(id, true, amap: amap)
            }
        }
        storeIDs = ids
        revision += 1
        persist()
    }

    // Revalidate on explicit addition; reuse valid conversions without another request.
    // Missing sources remain preview-only and never enter photo matching.
    func addHistory(_ id: String, amap: Bool) -> GpxTrackLog? {
        guard !activeIDs.contains(id), let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        do {
            let log = try GpxTrackLog(contentsOf: records[index].log.sourceURL)
            let fingerprint = records[index].fingerprint
            records[index].log = log
            records[index].sourceUnavailable = false
            if records[index].fingerprint != fingerprint {
                records[index].converted = nil; records[index].convertedAt = nil
            }
        } catch { records[index].sourceUnavailable = true }
        activeIDs.append(id)
        select(id, amap: amap)
        persist()
        return records[index].sourceUnavailable ? nil : records[index].log
    }

    func changeProvider(amap: Bool) {
        for id in Array(requests.keys) { cancel(id) }
        if amap {
            for record in activeRecords where visible.contains(record.id) {
                setVisible(record.id, true, amap: true)
            }
        }
    }

    func select(_ id: String, amap: Bool) {
        selected = id
        setVisible(id, true, amap: amap)
        fitRevision += 1
        revision += 1
    }

    func setVisible(_ id: String, _ value: Bool, amap: Bool) {
        guard let record = record(id) else { return }
        if value {
            visible.insert(id)
            if amap, !record.cacheIsCurrent, requests[id] == nil { start(id) }
        } else {
            visible.remove(id)
            cancel(id)
        }
        revision += 1
    }

    // Re-read only on explicit refresh, so changes to the source and its timestamps are picked up.
    func refresh(_ id: String, amap: Bool) -> GpxTrackLog? {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        do {
            let log = try GpxTrackLog(contentsOf: records[index].log.sourceURL)
            records[index].log = log
            records[index].sourceUnavailable = false
            // Keep the last successful geometry until the explicit refresh completes.
            cancel(id)
            if amap { start(id) }
            revision += 1
            persist()
            return log
        } catch {
            states[id] = .failed(L10n.text("无法读取原 GPX，请重新导入；已有缓存保留。"))
            return nil
        }
    }

    func start(_ id: String) {
        guard let record = record(id), !record.segments.isEmpty,
              record.segments.flatMap({ $0 }).allSatisfy(\.isValid) else {
            states[id] = .failed(L10n.text("没有有效线段可显示。"))
            return
        }
        sequence += 1
        requests[id] = sequence
        states[id] = .loading(0, record.segments.reduce(0) { $0 + $1.count })
        revision += 1
    }

    func cancel(_ id: String) {
        requests.removeValue(forKey: id)
        states.removeValue(forKey: id)
        revision += 1
    }

    func progress(_ id: String, request: Int, completed: Int, total: Int) {
        guard requests[id] == request, completed >= 0, completed <= total,
              total == record(id)?.segments.reduce(0, { $0 + $1.count }) else { return }
        states[id] = .loading(completed, total)
    }

    func complete(_ id: String, request: Int, converted: [[MapCoordinate]]) {
        guard requests[id] == request, let index = records.firstIndex(where: { $0.id == id }) else { return }
        guard TrackRecord.valid(converted, for: records[index].segments) else {
            fail(id, request: request, reason: L10n.text("高德返回的轨迹数据不完整。"))
            return
        }
        records[index].converted = converted
        records[index].convertedAt = Date()
        records[index].convertedSource = records[index].fingerprint
        requests.removeValue(forKey: id)
        states.removeValue(forKey: id)
        revision += 1
        persist()
    }

    func fail(_ id: String, request: Int, reason: String) {
        guard requests[id] == request else { return }
        requests.removeValue(forKey: id)
        states[id] = .failed(reason)
        revision += 1
    }

    func remove(_ id: String) {
        cancel(id)
        visible.remove(id)
        activeIDs.removeAll { $0 == id }
        if selected == id { selected = nil }
        revision += 1
        // History and its cache remain available for re-adding.
    }

    func clearCache(_ id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        cancel(id)
        visible.remove(id)
        records[index].converted = nil; records[index].convertedAt = nil
        persist()
        revision += 1
    }

    func displays(amap: Bool) -> [TrackDisplay] {
        records.filter { visible.contains($0.id) }.compactMap { record in
            let segments = amap ? record.converted : record.segments
            guard let segments else { return nil }
            return TrackDisplay(id: record.id,
                version: "\(record.fingerprint):\(record.convertedAt?.timeIntervalSince1970 ?? 0)", segments: segments)
        }
    }

}

private extension TrackLibrary {
    func bookmark(for source: URL) -> Data? {
        try? source.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                 includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private static func isPhotoGenerated(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let prefix = (try? handle.read(upToCount: 8_192)) ?? nil
        guard let prefix, let text = String(data: prefix, encoding: .utf8) else { return false }
        return text.contains("creator=\"PhotoTrail\"") && text.contains("<name>PhotoTrail Photos</name>")
    }

    private func persist() {
        guard !unreadable else { return }
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(Archive(records: records)).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            storageError = nil
        } catch { storageError = L10n.text("缓存保存失败，本次仍可查看；下次启动可能需要重新转换。") }
    }
}
