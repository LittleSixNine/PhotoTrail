import Exiftool
import ImageData
import Observation
import SwiftUI

/// One reader per window. Interactive jobs move ahead of waiting background jobs;
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
    var statuses: [ImageData.ID: Status] = [:]
    var originalCounts: [ImageData.ID: Int] = [:]
    var total = 0
    @ObservationIgnored private var targets: [ImageData.ID: MetadataInspectionRequest] = [:]
    @ObservationIgnored private var records: [MetadataInspectorReadCache.Key: Record] = [:]
    @ObservationIgnored private var jobs: [Job] = []
    @ObservationIgnored private var queuedKeys: Set<MetadataInspectorReadCache.Key> = []
    @ObservationIgnored private var current: Job?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var selectedIDs: Set<ImageData.ID> = []
    @ObservationIgnored private var waiters:
        [MetadataInspectorReadCache.Key: [CheckedContinuation<MetadataInspectorReadCache.Value?, Never>]] = [:]
    @ObservationIgnored private let reader: @Sendable (Job) async -> MetadataInspectorReadCache.Value?

    init(reader: @escaping @Sendable (Job) async -> MetadataInspectorReadCache.Value? = { job in
        await Task.detached(priority: job.priority < 2 ? .userInitiated : .utility) {
            MetadataLoadingQueue.load(job)
        }.value
    }) { self.reader = reader }

    var completed: Int { statuses.values.filter { $0 == .ready || $0 == .failed }.count }
    var failures: Int { statuses.values.filter { $0 == .failed }.count }

    func synchronize(_ images: [ImageData]) {
        targets = Dictionary(uniqueKeysWithValues: images.map {
            ($0.id, MetadataInspectionRequest(id: $0.id, url: $0.metadataInspectionURL,
                                             creatorImageURL: $0.metadataCreatorImageURL))
        })
        statuses = statuses.filter { targets[$0.key] != nil }
        originalCounts = originalCounts.filter { targets[$0.key] != nil }
        let retained = Set(targets.values.compactMap { key($0, kind: .editable) })
            .union(targets.values.compactMap { key($0, kind: .additional) })
        records = records.filter { retained.contains($0.key) }
        jobs.removeAll { targets[$0.request.id] != $0.request }
        queuedKeys = Set(jobs.map(\.key))
        // Resume consumers whose file was removed instead of leaving a suspended task.
        for removed in Array(waiters.keys).filter({ !retained.contains($0) }) {
            waiters.removeValue(forKey: removed)?.forEach { $0.resume(returning: nil) }
        }
        total = images.filter { $0.metadataInspectionURL != nil && $0.metadataCreatorImageURL != nil }.count
        for image in images {
            let request = targets[image.id]!
            guard key(request, kind: .editable) != nil else { statuses[image.id] = .unsupported; continue }
            enqueue(request, kind: .editable)
            enqueue(request, kind: .additional)
            updateStatus(request)
        }
        start()
    }

    func prioritize(ids: Set<ImageData.ID>) {
        selectedIDs = ids
        for index in jobs.indices { jobs[index].priority = rank(jobs[index].request, kind: jobs[index].key.kind) }
        jobs = jobs.filter { $0.priority == 0 } + jobs.filter { $0.priority == 1 } + jobs.filter { $0.priority == 2 }
    }

    func refresh(ids: Set<ImageData.ID>) {
        let urls = Set(ids.compactMap { targets[$0] }.flatMap { [$0.url, $0.creatorImageURL].compactMap { $0 } })
        MetadataInspectorReadCache.shared.invalidate(urls: urls)
        records = records.filter { !urls.contains($0.key.url) && !urls.contains($0.key.imageURL) }
        for id in ids {
            guard let request = targets[id] else { continue }
            originalCounts[id] = nil
            statuses[id] = .waiting
            enqueue(request, kind: .editable)
            enqueue(request, kind: .additional)
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
        guard current?.key != key, !queuedKeys.contains(key) else { return }
        let job = Job(request: request, key: key, priority: rank(request, kind: kind))
        if jobs.last.map({ $0.priority <= job.priority }) ?? true {
            jobs.append(job)
        } else {
            jobs.insert(job, at: jobs.firstIndex { $0.priority > job.priority } ?? jobs.endIndex)
        }
        queuedKeys.insert(key)
    }
    private func start() {
        guard worker == nil, !jobs.isEmpty else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while !jobs.isEmpty {
                let job = jobs.removeFirst()
                queuedKeys.remove(job.key)
                current = job
                statuses[job.request.id] = .reading
                let versions = job.request.versions
                let value = await reader(job)
                current = nil
                if targets[job.request.id] == job.request, job.request.versions == versions {
                    records[job.key] = Record(versions: versions, value: value)
                    if let value { MetadataInspectorReadCache.shared.insert(value, for: job.key, versions: versions) }
                    updateStatus(job.request)
                    waiters.removeValue(forKey: job.key)?.forEach { $0.resume(returning: value) }
                } else {
                    waiters.removeValue(forKey: job.key)?.forEach { $0.resume(returning: nil) }
                    if let latest = targets[job.request.id] {
                        enqueue(latest, kind: job.key.kind)
                        statuses[job.request.id] = .waiting
                    }
                }
                current = nil
            }
            worker = nil
        }
    }
    private func updateStatus(_ request: MetadataInspectionRequest) {
        guard let coreKey = key(request, kind: .editable), let fullKey = key(request, kind: .additional) else { return }
        let versions = request.versions
        let core = records[coreKey].flatMap { $0.versions == versions ? $0 : nil }
        let full = records[fullKey].flatMap { $0.versions == versions ? $0 : nil }
        if case .display(let tags) = full?.value {
            originalCounts[request.id] = Self.originalCount(tags)
        } else { originalCounts[request.id] = nil }
        if core != nil && full != nil {
            statuses[request.id] = core?.value == nil || full?.value == nil ? .failed : .ready
        } else { statuses[request.id] = current?.request.id == request.id ? .reading : .waiting }
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
                let legacy = try Exiftool.helper.legacyCreatorTags(from: imageURL)
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
