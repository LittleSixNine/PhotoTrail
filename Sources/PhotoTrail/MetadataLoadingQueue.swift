import Exiftool
import ImageData
import Observation
import SwiftUI

/// A bounded reader queue per window. Interactive jobs move ahead of waiting background jobs;
/// an already running ExifTool process is allowed to finish safely.
@Observable @MainActor
final class MetadataLoadingQueue {
    enum Status { case waiting, reading, ready, failed, unsupported }
    struct Job: Sendable {
        let request: MetadataInspectionRequest
        let key: MetadataInspectorReadCache.Key
        var priority: Int
    }
    private struct Record {
        let versions: [MetadataInspectionFileVersion]
        let value: MetadataInspectorReadCache.Value?
    }
    @Observable final class Row {
        var status: Status = .waiting
        var originalCount: Int?
        @ObservationIgnored var editableRead = false
        @ObservationIgnored var displayRead = false
    }
    @ObservationIgnored private var rows: [ImageData.ID: Row] = [:]
    var statuses: [ImageData.ID: Status] { rows.mapValues(\.status) }
    var originalCounts: [ImageData.ID: Int] { rows.compactMapValues(\.originalCount) }
    @Observable final class ReadProgress {
        var completed = 0
        var failures = 0
        var total = 0
        var editableRead = 0
        var displayRead = 0
        var isPaused = false
        var remainingSeconds: Double?
        private(set) var editableSecondsPerPhoto: Double?
        private(set) var displaySecondsPerPhoto: Double?
        var overallRemainingSeconds: Double? {
            let editable = editableRead >= total ? 0 : (editableEstimate.secondsPerUnit ?? editableSecondsPerPhoto)
                .map { Double(total - editableRead) * $0 }
            let display = displayRead >= total ? 0 : (displayEstimate.secondsPerUnit ?? displaySecondsPerPhoto)
                .map { Double(total - displayRead) * $0 }
            guard let editable, let display else { return nil }
            return editable + display
        }
        func estimatedSeconds(forPhotos count: Int) -> Double? {
            guard count > 0 else { return 0 }
            guard let editableSecondsPerPhoto, let displaySecondsPerPhoto else { return nil }
            return Double(count) * (editableSecondsPerPhoto + displaySecondsPerPhoto)
        }
        @ObservationIgnored private var editableEstimate = RemainingTimeEstimate()
        @ObservationIgnored private var displayEstimate = RemainingTimeEstimate()
        func resetTiming(now: Double = ProcessInfo.processInfo.systemUptime) {
            editableEstimate.reset(completed: editableRead, now: now)
            displayEstimate.reset(completed: displayRead, now: now)
            remainingSeconds = nil
        }
        func updateTiming(now: Double = ProcessInfo.processInfo.systemUptime) {
            editableEstimate.update(completed: editableRead, now: now)
            displayEstimate.update(completed: displayRead, now: now)
            if let rate = editableEstimate.secondsPerUnit { editableSecondsPerPhoto = rate }
            if let rate = displayEstimate.secondsPerUnit { displaySecondsPerPhoto = rate }
            remainingSeconds = editableRead < total
                ? editableEstimate.seconds(total: total) : displayEstimate.seconds(total: total)
        }
    }
    let progress = ReadProgress()
    var completed: Int { progress.completed }
    var failures: Int { progress.failures }
    var total: Int { progress.total }
    private(set) var isPreparing = false
    @ObservationIgnored private var userPaused = false
    @ObservationIgnored private let maxConcurrentReads: Int
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var targets: [ImageData.ID: MetadataInspectionRequest] = [:]
    @ObservationIgnored private var records: [MetadataInspectorReadCache.Key: Record] = [:]
    @ObservationIgnored private var jobs: [Job] = []
    @ObservationIgnored private var queuedKeys: Set<MetadataInspectorReadCache.Key> = []
    @ObservationIgnored private var current: [Job] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var selectedIDs: Set<ImageData.ID> = []
    @ObservationIgnored private var waiters:
        [MetadataInspectorReadCache.Key: [CheckedContinuation<MetadataInspectorReadCache.Value?, Never>]] = [:]
    @ObservationIgnored private let reader: @Sendable (Job) async -> MetadataInspectorReadCache.Value?

    init(maxConcurrentReads: Int = min(4, max(1, ProcessInfo.processInfo.activeProcessorCount - 2)), reader: @escaping @Sendable (Job) async -> MetadataInspectorReadCache.Value? = { job in
        await Task.detached(priority: job.priority < 2 ? .userInitiated : .utility) {
            MetadataLoadingQueue.load(job)
        }.value
    }) {
        self.reader = reader
        self.maxConcurrentReads = max(1, min(4, maxConcurrentReads))
    }

    func row(for id: ImageData.ID) -> Row {
        if let row = rows[id] { return row }
        let row = Row()
        rows[id] = row
        return row
    }

    private func setStatus(_ status: Status, for id: ImageData.ID) {
        let row = row(for: id)
        let wasCompleted = row.status == .ready || row.status == .failed
        let isCompleted = status == .ready || status == .failed
        if wasCompleted != isCompleted { progress.completed += isCompleted ? 1 : -1 }
        if (status == .failed) != (row.status == .failed) { progress.failures += status == .failed ? 1 : -1 }
        if row.status != status { row.status = status }
    }

    func setPaused(_ value: Bool) {
        if paused != value { progress.resetTiming() }
        paused = value
        if !value { start() }
    }

    func pauseReading() {
        progress.resetTiming()
        userPaused = true
        progress.isPaused = true
        isPreparing = false
    }

    func resumeReading() {
        progress.resetTiming()
        userPaused = false
        progress.isPaused = false
        start()
    }

    func synchronize(_ images: [ImageData]) {
        let previousTargets = targets
        targets = Dictionary(uniqueKeysWithValues: images.map {
            ($0.id, MetadataInspectionRequest(id: $0.id, url: $0.metadataInspectionURL,
                                             creatorImageURL: $0.metadataCreatorImageURL))
        })
        rows = rows.filter { targets[$0.key] != nil }
        progress.completed = rows.values.filter { $0.status == .ready || $0.status == .failed }.count
        progress.failures = rows.values.filter { $0.status == .failed }.count
        let retained = Set(targets.values.compactMap { key($0, kind: .editable) })
            .union(targets.values.compactMap { key($0, kind: .additional) })
        records = records.filter { retained.contains($0.key) }
        jobs.removeAll { targets[$0.request.id] != $0.request }
        queuedKeys = Set(jobs.map(\.key))
        // Resume consumers whose file was removed instead of leaving a suspended task.
        for removed in Array(waiters.keys).filter({ !retained.contains($0) }) {
            waiters.removeValue(forKey: removed)?.forEach { $0.resume(returning: nil) }
        }
        progress.editableRead = rows.values.filter(\.editableRead).count
        progress.displayRead = rows.values.filter(\.displayRead).count
        progress.total = images.filter { $0.metadataInspectionURL != nil && $0.metadataCreatorImageURL != nil }.count
        for image in images {
            let request = targets[image.id]!
            guard key(request, kind: .editable) != nil else { setStatus(.unsupported, for: image.id); continue }
            enqueue(request, kind: .editable)
            enqueue(request, kind: .additional)
            updateStatus(request)
        }
        if previousTargets != targets { progress.resetTiming() }
        // Re-reading saved files must not replace the current workspace and discard its scroll position.
        let addedIDs = Set(targets.keys).subtracting(previousTargets.keys)
        if !userPaused && Set(jobs.map { $0.request.id }).intersection(addedIDs).count >= 100 { isPreparing = true }
        if jobs.isEmpty && current.isEmpty { isPreparing = false }
        start()
    }

    func prioritize(ids: Set<ImageData.ID>) {
        selectedIDs = ids
        for index in jobs.indices { jobs[index].priority = rank(jobs[index].request, kind: jobs[index].key.kind) }
        jobs = jobs.filter { $0.priority == 0 } + jobs.filter { $0.priority == 1 } + jobs.filter { $0.priority == 2 }
    }

    func refresh(ids: Set<ImageData.ID>) {
        let urls = Set(ids.compactMap { targets[$0] }.flatMap { [$0.url, $0.creatorImageURL].compactMap { $0 } })
        progress.resetTiming()
        MetadataInspectorReadCache.shared.invalidate(urls: urls)
        records = records.filter { !urls.contains($0.key.url) && !urls.contains($0.key.imageURL) }
        for id in ids {
            guard let request = targets[id] else { continue }
            row(for: id).originalCount = nil
            setStatus(.waiting, for: id)
            enqueue(request, kind: .editable)
            enqueue(request, kind: .additional)
            updateStatus(request)
        }
        start()
    }

    func hasCached(_ request: MetadataInspectionRequest, kind: MetadataInspectorReadCache.Kind) -> Bool {
        guard targets[request.id] == request, let key = key(request, kind: kind),
              let record = records[key] else { return false }
        return record.versions == request.versions
    }

    func read(_ request: MetadataInspectionRequest, kind: MetadataInspectorReadCache.Kind) async
        -> MetadataInspectorReadCache.Value? {
        guard targets[request.id] == request, let key = key(request, kind: kind) else { return nil }
        let versions = request.versions
        if let record = records[key], record.versions == versions { return record.value }
        if let cached = MetadataInspectorReadCache.shared.value(for: key, versions: versions) {
            records[key] = Record(versions: versions, value: cached)
            updateStatus(request)
            return cached
        }
        return await withCheckedContinuation { continuation in
            waiters[key, default: []].append(continuation)
            enqueue(request, kind: kind)
            start()
        }
    }

    private func key(_ request: MetadataInspectionRequest, kind: MetadataInspectorReadCache.Kind)
        -> MetadataInspectorReadCache.Key? {
        guard let url = request.url, let imageURL = request.creatorImageURL else { return nil }
        return .init(url: url, imageURL: imageURL, kind: kind)
    }
    private func rank(_ request: MetadataInspectionRequest, kind: MetadataInspectorReadCache.Kind) -> Int {
        selectedIDs.contains(request.id) ? (kind == .editable ? 0 : 1) : 2
    }
    private func enqueue(_ request: MetadataInspectionRequest, kind: MetadataInspectorReadCache.Kind) {
        guard let key = key(request, kind: kind) else { return }
        if let record = records[key], record.versions == request.versions { return }
        guard !current.contains(where: { $0.key == key }), !queuedKeys.contains(key) else { return }
        let job = Job(request: request, key: key, priority: rank(request, kind: kind))
        if jobs.last.map({ $0.priority <= job.priority }) ?? true {
            jobs.append(job)
        } else {
            jobs.insert(job, at: jobs.firstIndex { $0.priority > job.priority } ?? jobs.endIndex)
        }
        queuedKeys.insert(key)
    }
    private func start() {
        guard !paused, !userPaused, worker == nil, !jobs.isEmpty else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while !paused && !userPaused && !jobs.isEmpty {
                let batch = Array(jobs.prefix(maxConcurrentReads))
                jobs.removeFirst(batch.count)
                current = batch
                for job in batch {
                    queuedKeys.remove(job.key)
                    setStatus(.reading, for: job.request.id)
                }
                await withTaskGroup(of: (Job, [MetadataInspectionFileVersion], MetadataInspectorReadCache.Value?).self) { group in
                    for job in batch {
                        let versions = job.request.versions
                        group.addTask { [reader] in (job, versions, await reader(job)) }
                    }
                    for await (job, versions, value) in group {
                        current.removeAll { $0.key == job.key }
                        if targets[job.request.id] == job.request, job.request.versions == versions {
                            records[job.key] = Record(versions: versions, value: value)
                            if let value { MetadataInspectorReadCache.shared.insert(value, for: job.key, versions: versions) }
                            updateStatus(job.request)
                            waiters.removeValue(forKey: job.key)?.forEach { $0.resume(returning: value) }
                        } else {
                            waiters.removeValue(forKey: job.key)?.forEach { $0.resume(returning: nil) }
                            if let latest = targets[job.request.id] {
                                enqueue(latest, kind: job.key.kind)
                                updateStatus(latest)
                            }
                        }
                    }
                }
            }
            worker = nil
            if jobs.isEmpty { isPreparing = false }
        }
    }
    private func updateStatus(_ request: MetadataInspectionRequest) {
        guard let coreKey = key(request, kind: .editable), let fullKey = key(request, kind: .additional) else { return }
        let versions = request.versions
        let core = records[coreKey].flatMap { $0.versions == versions ? $0 : nil }
        let full = records[fullKey].flatMap { $0.versions == versions ? $0 : nil }
        let row = row(for: request.id)
        if row.editableRead != (core != nil) {
            progress.editableRead += core != nil ? 1 : -1
            row.editableRead = core != nil
        }
        if row.displayRead != (full != nil) {
            progress.displayRead += full != nil ? 1 : -1
            row.displayRead = full != nil
        }
        progress.updateTiming()
        let count: Int?
        if case .display(let tags) = full?.value { count = Self.originalCount(tags) }
        else { count = nil }
        if row.originalCount != count { row.originalCount = count }
        if core != nil && full != nil {
            setStatus(core?.value == nil || full?.value == nil ? .failed : .ready, for: request.id)
        } else { setStatus(current.contains { $0.request.id == request.id } ? .reading : .waiting, for: request.id) }
    }
    static func originalCount(_ tags: [String: String]) -> Int {
        tags.keys.filter {
            let name = $0.hasPrefix("Image/") ? String($0.dropFirst(6)) : $0
            return !name.hasPrefix("File:") && !name.hasPrefix("System:")
                && !name.hasPrefix("Composite:") && !name.hasPrefix("ExifTool:")
        }.count
    }
    func editedCount(_ image: ImageData) -> Int {
        var count = image.creatorDraft?.changes.count ?? 0
        if let request = targets[image.id], let key = key(request, kind: .editable),
           case .editable(let snapshot, _) = records[key]?.value, snapshot.version == image.creatorDraft?.version {
            count = image.creatorDraft?.changes.filter { tag, change in
                switch change {
                case .remove: snapshot.values[tag] != nil
                case .set(let value): !(snapshot.values[tag].map { tag.matches($0, value) } ?? false)
                }
            }.count ?? 0
        }
        if image.hasLegacyChanges, let original = image.original {
            let changed = [image.creatorDraft?.captureDateChange == nil
                && image.metadata.dateTimeCreated != original.dateTimeCreated,
                image.metadata.location?.latitude != original.location?.latitude,
                image.metadata.location?.longitude != original.location?.longitude,
                image.metadata.elevation != original.elevation, image.metadata.gpsMapDatum != original.gpsMapDatum,
                image.metadata.gpsProcessingMethod != original.gpsProcessingMethod,
                image.metadata.sublocation != original.sublocation,
                image.metadata.city != original.city,
                image.metadata.state != original.state, image.metadata.country != original.country,
                image.metadata.countryCode != original.countryCode]
            count += changed.filter { $0 }.count
        }
        return count
    }
    nonisolated private static func load(_ job: Job) -> MetadataInspectorReadCache.Value? {
        let request = job.request
        let before = request.versions
        if let cached = MetadataInspectorReadCache.shared.value(for: job.key, versions: before) { return cached }
        guard let url = request.url, let imageURL = request.creatorImageURL else { return nil }
        do {
            let value: MetadataInspectorReadCache.Value
            if job.key.kind == .editable {
                let snapshot = try MetadataInspectionSnapshot.read(Set(MetadataTag.allCases), from: url)
                let legacy: [LegacyCreatorTag: [String]]
                if imageURL == url {
                    // These exact compatibility fields are already in the typed whitelist read.
                    var existing: [LegacyCreatorTag: [String]] = [:]
                    if case .text(let artist) = snapshot.values[.exifArtist] { existing[.exifArtist] = [artist] }
                    if case .list(let byline) = snapshot.values[.iptcByline] { existing[.iptcByline] = byline }
                    legacy = existing
                } else {
                    legacy = try Exiftool.helper.legacyCreatorTags(from: imageURL)
                }
                value = .editable(snapshot, legacy)
            } else {
                var tags = try Exiftool.helper.inspectionTags(from: url)
                if imageURL != url {
                    let imageTags = try Exiftool.helper.inspectionTags(from: imageURL)
                    for (name, value) in imageTags where !name.hasPrefix("XMP") { tags["Image/" + name] = value }
                }
                value = .display(tags)
            }
            return request.versions == before ? value : nil
        } catch { return nil }
    }
}
