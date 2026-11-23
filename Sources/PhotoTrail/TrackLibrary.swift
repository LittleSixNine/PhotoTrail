import Coords
import CryptoKit
import Foundation
import GpxTrackLog
import ImageData
import Observation

enum TrackOrigin: String, Codable, Sendable {
    case photos
}

struct TrackRecord: Codable, Identifiable, Equatable, Sendable {
    var log: GpxTrackLog { didSet { rebuildGeometry() } }
    private(set) var segments: [[MapCoordinate]] = []
    private(set) var fingerprint = ""

    private enum CodingKeys: String, CodingKey {
        case log, originalLog, bookmark, converted, convertedAt, convertedSource, origin, sourceUnavailable, ownedVersion
    }
    init(log: GpxTrackLog, bookmark: Data? = nil, origin: TrackOrigin? = nil) {
        self.log = log
        self.bookmark = bookmark
        self.origin = origin
        rebuildGeometry()
    }
    var originalLog: GpxTrackLog? = nil
    var bookmark: Data?
    var converted: [[MapCoordinate]]?
    var convertedAt: Date?
    var convertedSource: String?
    var ownedVersion: MetadataInspectionFileVersion?
    var origin: TrackOrigin? = nil
    var cacheIsCurrent: Bool { converted != nil && convertedSource == fingerprint }
    var sourceUnavailable = false
    var id: String { log.sourceURL.path }
    var name: String { log.sourceURL.lastPathComponent }
    var generatedFromPhotos: Bool { origin == .photos }
    var points: [GpxTrackLog.Point] { log.tracks.flatMap(\.segments).flatMap(\.points) }
    mutating func rebuildGeometry() {
        segments = log.tracks.flatMap(\.segments).map { $0.points.map {
            MapCoordinate(latitude: $0.lat, longitude: $0.lon)
        } }.filter { $0.count >= 2 }
        // Preserve the v1 geometry fingerprint across application upgrades.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(segments)) ?? Data()
        fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
    private(set) var archiveRevision = 0
    private(set) var revision = 0
    private(set) var fitRevision = 0
    var storageError: String?
    @ObservationIgnored private let url: URL
    @ObservationIgnored private let writes = DispatchQueue(label: "PhotoTrail.track-history", qos: .utility)
    @ObservationIgnored private var pendingWrite: DispatchWorkItem?
    @ObservationIgnored private var writeID = UUID()
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var unreadable = false
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var storeIDs: Set<String> = []
    private(set) var restoring = false
    private(set) var readingSources: [String: UUID] = [:]
    @ObservationIgnored private var restoreTask: Task<[TrackRecord], Error>?
    @ObservationIgnored private var needsPersist = false
    @ObservationIgnored private let legacyURL: URL?
    @ObservationIgnored private var adjustmentUndo: [String: GpxTrackLog] = [:]
    @ObservationIgnored private var photoGeneratedURLs: Set<String> = []

    private struct Archive: Codable, Sendable {
        var version = 1
        var records: [TrackRecord]
    }

    init(url: URL? = nil) {
        let current = url ?? URL.applicationSupportDirectory
            .appendingPathComponent("PhotoTrail/Tracks/cache-v1.json")
        legacyURL = url == nil ? URL.applicationSupportDirectory
            .appendingPathComponent("GeoTagCN/Tracks/cache-v1.json") : nil
        self.url = current
        loaded = !FileManager.default.fileExists(atPath: current.path)
            && !(legacyURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
    }

    func record(_ id: String) -> TrackRecord? { records.first { $0.id == id } }

    func markPhotoGenerated(_ url: URL) {
        photoGeneratedURLs.insert(url.standardizedFileURL.path)
    }

    // Historical geometry is restored without reopening every original file.
    func restore() async {
        guard !loaded else { return }
        let task: Task<[TrackRecord], Error>
        if let existing = restoreTask { task = existing }
        else {
            let url = url, legacy = legacyURL
            task = Task.detached(priority: .utility) { try Self.readArchive(at: url, legacy: legacy) }
            restoreTask = task
            restoring = true
        }
        do {
            let saved = try await task.value
            guard !loaded else { return }
            let currentIDs = Set(records.map(\.id))
            records = saved.filter { !currentIDs.contains($0.id) } + records
            revision += 1
        } catch {
            guard !loaded else { return }
            unreadable = true
            storageError = L10n.text("轨迹缓存无法读取，原文件已保留。可重新导入轨迹；本次转换结果仅在内存中保留。")
        }
        loaded = true; restoring = false; restoreTask = nil
        if needsPersist { needsPersist = false; persist() }
    }

    @discardableResult
    func synchronize(_ logs: [GpxTrackLog], amap: Bool = false) -> [GpxTrackLog] {
        guard !logs.isEmpty || !storeIDs.isEmpty else { return logs }
        let ids = Set(logs.map { $0.sourceURL.path })
        for id in storeIDs.subtracting(ids) { remove(id) }
        var needsArchive = false
        for incoming in logs {
            var log = incoming
            let id = log.sourceURL.path
            if let index = records.firstIndex(where: { $0.id == id }),
               let original = records[index].originalLog, incoming != records[index].log {
                guard incoming.tracks == original.tracks else {
                    needsArchive = true
                    records[index].sourceUnavailable = true
                    cancel(id)
                    states[id] = .failed(L10n.text("原轨迹已变化，保留调整；请恢复原轨迹后重新调整。"))
                    continue
                }
                log = records[index].log
            }
            var changed = false
            if let index = records.firstIndex(where: { $0.id == id }) {
                if records[index].log != log || records[index].sourceUnavailable {
                    needsArchive = true
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
                needsArchive = true
                let owned = photoGeneratedURLs.remove(id) != nil
                var record = TrackRecord(log: log, bookmark: bookmark(for: log.sourceURL),
                                         origin: owned || Self.isPhotoGenerated(log.sourceURL) ? .photos : nil)
                if owned { record.ownedVersion = .read(log.sourceURL) }
                records.append(record)
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
        if needsArchive { persist() }
        return logs.compactMap { input in
            guard let record = record(input.sourceURL.path), !record.sourceUnavailable else { return nil }
            return record.log
        }
    }

    // Missing sources remain preview-only and never enter photo matching.
    func addHistory(_ id: String, amap: Bool) async -> GpxTrackLog? {
        guard !activeIDs.contains(id) else { return nil }
        guard let result = await readSource(id) else { return nil }
        let log: GpxTrackLog?
        switch result {
        case .success(let value):
            let newID = value.sourceURL.path
            if !activeIDs.contains(newID) { activeIDs.append(newID) }
            select(newID, amap: amap)
            log = value
        case .failure:
            if !activeIDs.contains(id) { activeIDs.append(id) }
            select(id, amap: false)
            log = nil
        }
        persist()
        return log
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

    // Keep the last successful geometry while an explicit refresh is reading.
    func refresh(_ id: String, amap: Bool) async -> GpxTrackLog? {
        guard case .success(let log) = await readSource(id, preserveCache: true) else { return nil }
        let newID = log.sourceURL.path
        cancel(id)
        if amap { start(newID) }
        revision += 1
        persist()
        return log
    }

    private func readSource(_ id: String, preserveCache: Bool = false) async -> Result<GpxTrackLog, Error>? {
        guard readingSources[id] == nil, let original = record(id) else { return nil }
        let token = UUID()
        readingSources[id] = token
        defer { if readingSources[id] == token { readingSources.removeValue(forKey: id) } }
        do {
            let updated = try await Task.detached(priority: .userInitiated) {
                try Self.readSource(original, preserveCache: preserveCache)
            }.value
            guard readingSources[id] == token, record(id) == original,
                  let index = records.firstIndex(where: { $0.id == id }) else { return nil }
            records[index] = updated
            if updated.id != id {
                activeIDs = activeIDs.map { $0 == id ? updated.id : $0 }
                if visible.remove(id) != nil { visible.insert(updated.id) }
                if selected == id { selected = updated.id }
                if storeIDs.remove(id) != nil { storeIDs.insert(updated.id) }
                cancel(id)
            }
            revision += 1
            return .success(updated.log)
        } catch {
            guard readingSources[id] == token, record(id) == original,
                  let index = records.firstIndex(where: { $0.id == id }) else { return nil }
            records[index].sourceUnavailable = true
            states[id] = .failed(L10n.text("无法读取原轨迹，请重新导入；已有缓存保留。"))
            revision += 1
            return .failure(error)
        }
    }

    nonisolated private static func readSource(_ original: TrackRecord, preserveCache: Bool) throws -> TrackRecord {
        var source = original.log.sourceURL
        if let bookmark = original.bookmark {
            var stale = false
            source = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                             bookmarkDataIsStale: &stale)
        }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var record = original
        let version = MetadataInspectionFileVersion.read(source)
        let sourceLog = try GpxTrackLog(contentsOf: source)
        if let originalLog = original.originalLog {
            guard sourceLog.tracks == originalLog.tracks else { throw MetadataInspectionError.sourceChanged }
            record.log = GpxTrackLog(sourceURL: source, tracks: original.log.tracks)
        } else { record.log = sourceLog }
        guard version == MetadataInspectionFileVersion.read(source) else { throw MetadataInspectionError.sourceChanged }
        record.bookmark = try? source.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
        record.sourceUnavailable = false
        if !preserveCache, record.fingerprint != original.fingerprint {
            record.converted = nil; record.convertedAt = nil
        }
        return record
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
        readingSources.removeValue(forKey: id)
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

    var conversionCacheCount: Int { records.filter { $0.converted != nil }.count }
    var cacheFileSize: Int64 { Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    var canClearConversionCaches: Bool { loaded && !unreadable && readingSources.isEmpty && conversionCacheCount > 0 }

    func clearConversionCaches() async throws {
        guard canClearConversionCaches else { throw CocoaError(.fileWriteUnknown) }
        var updated = records
        for index in updated.indices {
            updated[index].converted = nil
            updated[index].convertedAt = nil
            updated[index].convertedSource = nil
        }
        // Commit first; a failed write must leave the current cache usable.
        try await writeArchive(updated)
        records = updated
        requests.removeAll(); states.removeAll()
        storageError = nil
        revision += 1
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

    nonisolated private static func isPhotoGenerated(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let prefix = (try? handle.read(upToCount: 8_192)) ?? nil
        guard let prefix, let text = String(data: prefix, encoding: .utf8) else { return false }
        return text.contains("creator=\"PhotoTrail\"") && text.contains("<name>PhotoTrail Photos</name>")
    }

    private func persist() {
        guard loaded else { needsPersist = true; return }
        guard !unreadable else { return }
        pendingWrite?.cancel()
        let token = UUID(), snapshot = records, destination = url
        writeID = token
        let work = DispatchWorkItem { @Sendable [weak self] in
            let result = Result { try Self.save(snapshot, to: destination) }
            Task { @MainActor in
                guard let self, self.writeID == token else { return }
                self.pendingWrite = nil
                switch result {
                case .success:
                    self.storageError = nil
                    self.archiveRevision += 1
                case .failure(let error):
                    let message = OperationFailure.message(L10n.text("缓存保存失败，本次仍可查看；下次启动可能需要重新转换。"), error: error)
                    if self.storageError != message { OperationFailure.present(message) }
                    self.storageError = message
                }
            }
        }
        pendingWrite = work
        writes.async(execute: work)
    }

    private func writeArchive(_ updated: [TrackRecord]) async throws {
        let destination = url, generation = revision, pendingID = writeID
        // Stage on the same volume, behind prior writes. Only the final atomic rename
        // runs on the main actor, together with the caller's in-memory commit.
        let temporary = try await withCheckedThrowingContinuation { (reply: CheckedContinuation<URL, Error>) in
            writes.async { @Sendable in
                reply.resume(with: Result {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                             appropriateFor: destination, create: true)
                    do { try Self.save(updated, to: folder.appendingPathComponent("archive")) }
                    catch { try? FileManager.default.removeItem(at: folder); throw error }
                    return folder
                })
            }
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard generation == revision, pendingID == writeID else { throw MetadataInspectionError.sourceChanged }
        guard rename(temporary.appendingPathComponent("archive").path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        writeID = UUID()
        pendingWrite = nil
        archiveRevision += 1
    }

    nonisolated private static func save(_ records: [TrackRecord], to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(Archive(records: records)).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

}

extension TrackLibrary {
    func applyAdjustment(_ id: String, expected: GpxTrackLog, adjusted: GpxTrackLog, amap: Bool) async throws {
        guard loaded, !unreadable, readingSources[id] == nil,
              let index = records.firstIndex(where: { $0.id == id }), records[index].log == expected,
              adjusted.sourceURL == expected.sourceURL else { throw MetadataInspectionError.sourceChanged }
        let current = records[index]
        let source = try await Task.detached { try Self.readSource(current, preserveCache: true) }.value
        guard records.indices.contains(index), records[index] == current else { throw MetadataInspectionError.sourceChanged }
        guard source.log == expected else { throw MetadataInspectionError.sourceChanged }
        var updated = records
        updated[index].originalLog = current.originalLog ?? expected
        updated[index].log = adjusted
        if current.fingerprint != updated[index].fingerprint {
            updated[index].converted = nil; updated[index].convertedAt = nil; updated[index].convertedSource = nil
        }
        try await writeArchive(updated)
        adjustmentUndo[id] = expected
        records = updated
        if selected == id, current.fingerprint != records[index].fingerprint { fitRevision += 1 }
        cancel(id)
        if amap && visible.contains(id) && !records[index].cacheIsCurrent { start(id) }
        revision += 1
    }

    func undoAdjustment(_ id: String, amap: Bool) async throws -> GpxTrackLog? {
        guard let previous = adjustmentUndo[id], let current = record(id) else { return nil }
        try await applyAdjustment(id, expected: current.log, adjusted: previous, amap: amap)
        adjustmentUndo.removeValue(forKey: id)
        return previous
    }

    func canUndoAdjustment(_ id: String) -> Bool { adjustmentUndo[id] != nil }

    func restoreOriginal(_ id: String, amap: Bool) async throws -> GpxTrackLog? {
        guard let index = records.firstIndex(where: { $0.id == id }), records[index].originalLog != nil,
              loaded, !unreadable else { return nil }
        var source = records[index]
        source.originalLog = nil
        let expected = records[index]
        let restored = try await Task.detached { [source] in try Self.readSource(source, preserveCache: false) }.value
        guard records.indices.contains(index), records[index] == expected else { throw MetadataInspectionError.sourceChanged }
        var updated = records
        updated[index] = restored
        updated[index].converted = nil; updated[index].convertedAt = nil; updated[index].convertedSource = nil
        try await writeArchive(updated)
        if selected == id, records[index].fingerprint != restored.fingerprint { fitRevision += 1 }
        records = updated
        adjustmentUndo.removeValue(forKey: id)
        cancel(id)
        if amap && visible.contains(id) { start(id) }
        revision += 1
        return restored.log
    }

}

extension TrackLibrary {
    nonisolated private static func readArchive(at url: URL, legacy: URL?) throws -> [TrackRecord] {
        if let legacy { PhotoTrailMigration.file(at: url, legacyURL: legacy) }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
        guard archive.version == 1, Set(archive.records.map(\.id)).count == archive.records.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var validated = try archive.records.map { saved in
            var record = saved
            record.rebuildGeometry()
            guard record.originalLog.map({ base in
                base.sourceURL == record.log.sourceURL && base.tracks.flatMap(\.segments).flatMap(\.points).allSatisfy {
                    $0.lat.isFinite && $0.lon.isFinite && abs($0.lat) <= 90 && abs($0.lon) <= 180
                        && (!$0.hasRecordedTime || $0.timeFromEpoch.isFinite)
                }
            }) ?? true, record.log.sourceURL.isFileURL,
                  record.points.allSatisfy({ $0.lat.isFinite && $0.lon.isFinite && abs($0.lat) <= 90 && abs($0.lon) <= 180 }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if let converted = record.converted,
               !TrackRecord.valid(converted, for: record.segments) || !record.cacheIsCurrent {
                record.converted = nil; record.convertedAt = nil
            }
            return record
        }
        if legacy != nil {
            var updated = validated
            let migrated = migrateGenerated(&updated, old: PhotoGPXDocument.legacyDirectory,
                                             new: PhotoGPXDocument.generatedDirectory)
            if !migrated.isEmpty {
                // Old references remain usable if the archive cannot be committed.
                do { try save(updated, to: url) } catch { return validated }
                validated = updated
                for (source, identity) in migrated where identity == MetadataInspectionFileVersion.read(source) {
                    if case .file = identity { _ = unlink(source.path) }
                }
            }
        }
        return validated
    }

    nonisolated static func migrateGenerated(_ records: inout [TrackRecord], old: URL, new: URL)
        -> [URL: MetadataInspectionFileVersion] {
        var migrated: [URL: MetadataInspectionFileVersion] = [:]
        var occupied = Set(records.map { $0.log.sourceURL.standardizedFileURL.path })
        for index in records.indices {
            let record = records[index], source = record.log.sourceURL
            guard source.deletingLastPathComponent().standardizedFileURL.path == old.standardizedFileURL.path,
                  source.pathExtension.lowercased() == "gpx" else { continue }
            let identity = MetadataInspectionFileVersion.read(source)
            let bytes: Data
            do {
                if identity == .missing, record.generatedFromPhotos {
                    // Recover the geometry and times when an older cache was already purged.
                    bytes = try (record.originalLog ?? record.log).gpxData()
                } else {
                    guard (try? source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                          record.generatedFromPhotos || isPhotoGenerated(source) else { continue }
                    bytes = try Data(contentsOf: source)
                }
                guard identity == MetadataInspectionFileVersion.read(source) else { continue }
                let destination = try PhotoGPXDocument.store(bytes, name: source.lastPathComponent, in: new,
                                                             reuseIdentical: true, excluding: occupied)
                occupied.insert(destination.standardizedFileURL.path)
                records[index].log = GpxTrackLog(sourceURL: destination, tracks: record.log.tracks)
                records[index].originalLog = record.originalLog.map { GpxTrackLog(sourceURL: destination, tracks: $0.tracks) }
                records[index].bookmark = nil
                records[index].sourceUnavailable = false
                records[index].origin = .photos
                records[index].ownedVersion = .read(destination)
                migrated[source] = identity
            } catch { continue } // Keep this reference for retry without blocking unrelated history.
        }
        return migrated
    }
}

extension TrackLibrary {
    func flushWrites() { writes.sync {} }

    func forget(_ id: String) async throws {
        guard loaded, !unreadable, !activeIDs.contains(id), readingSources[id] == nil,
              let index = records.firstIndex(where: { $0.id == id }) else { throw CocoaError(.fileWriteUnknown) }
        var updated = records
        let removed = updated.remove(at: index)
        try await writeArchive(updated)
        records = updated
        adjustmentUndo.removeValue(forKey: id)
        cancel(id)
        let source = removed.log.sourceURL
        if let version = removed.ownedVersion, case .file = version, version == .read(source),
           source.deletingLastPathComponent().standardizedFileURL.path == PhotoGPXDocument.generatedDirectory.standardizedFileURL.path,
           (try? source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            guard unlink(source.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
    }
}
