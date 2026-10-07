import Exiftool
import Foundation
import ImageData
import Metadata
import Testing
@testable import PhotoTrail

private actor QueueReaderProbe {
    var jobs: [MetadataLoadingQueue.Job] = []
    private var firstWaiter: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    let blockFirst: Bool
    let fail: Bool
    init(blockFirst: Bool = false, fail: Bool = false) {
        self.blockFirst = blockFirst
        self.fail = fail
    }
    func read(_ job: MetadataLoadingQueue.Job) async -> MetadataInspectorReadCache.Value? {
        jobs.append(job)
        firstWaiter?.resume()
        firstWaiter = nil
        if blockFirst && jobs.count == 1 {
            await withCheckedContinuation { release = $0 }
        }
        return fail ? nil : .display(["ExifIFD:ISO": "100", "XMP-dc:Subject": "[a,b]", "File:FileSize": "1"])
    }
    func waitForFirst() async {
        if jobs.isEmpty { await withCheckedContinuation { firstWaiter = $0 } }
    }
    func unblock() { release?.resume(); release = nil }
}

private actor BoundedReaderProbe {
    var active = 0
    var maximum = 0
    var reads = 0
    func read(_ job: MetadataLoadingQueue.Job) async -> MetadataInspectorReadCache.Value? {
        active += 1
        maximum = max(maximum, active)
        reads += 1
        try? await Task.sleep(for: .milliseconds(10))
        active -= 1
        return .display([:])
    }
}

@MainActor struct MetadataLoadingQueueTests {
    private func image(_ directory: URL, _ name: String) throws -> ImageData {
        let url = directory.appendingPathComponent(name + ".jpg")
        try Data("test".utf8).write(to: url)
        var metadata = Metadata(source: .image(url))
        metadata.readable = false // Queue scheduling tests never invoke a real parser.
        return ImageData(metadata: metadata, name: name)
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func request(_ image: ImageData) -> MetadataInspectionRequest {
        .init(id: image.id, url: image.metadataInspectionURL, creatorImageURL: image.metadataCreatorImageURL)
    }
    private func finish(_ queue: MetadataLoadingQueue, _ images: [ImageData]) async {
        for image in images {
            _ = await queue.read(request(image), kind: .editable)
            _ = await queue.read(request(image), kind: .additional)
        }
    }
    @Test(arguments: [2, 4]) func boundedReadsDeduplicateAndTrackBothStages(concurrency: Int) async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let images = try (0..<6).map { try image(dir, "bounded-\($0)") }
        let probe = BoundedReaderProbe()
        let queue = MetadataLoadingQueue(maxConcurrentReads: concurrency, reader: { await probe.read($0) })
        queue.synchronize(images)
        queue.synchronize(images)
        await finish(queue, images)
        #expect(await probe.maximum == concurrency)
        #expect(await probe.reads == 12)
        #expect(queue.progress.editableRead == 6 && queue.progress.displayRead == 6)
        queue.setPaused(true)
        queue.refresh(ids: [images[0].id])
        #expect(queue.progress.editableRead == 5 && queue.progress.displayRead == 5)
        queue.setPaused(false)
        await finish(queue, images)
        #expect(await probe.reads == 14)
    }
    @Test func largeImportPreparationCanPauseAndResumeWithoutLosingWork() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let images = try (0..<100).map { try image(dir, "large-\($0)") }
        let probe = BoundedReaderProbe()
        let queue = MetadataLoadingQueue(reader: { await probe.read($0) })
        queue.synchronize(images)
        #expect(queue.isPreparing)
        queue.pauseReading()
        await Task.yield()
        #expect(!queue.isPreparing && queue.progress.isPaused)
        #expect(await probe.reads == 0)
        queue.resumeReading()
        await finish(queue, images)
        // Let the worker clear its phase after delivering the final read.
        await Task.yield()
        #expect(queue.completed == 100 && !queue.progress.isPaused)
        #expect(!queue.isPreparing)
        #expect(await probe.reads == 200)
    }
    @Test func selectionJumpsWaitingJobsAndCachedReselectionDoesNotReadAgain() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let images = try [image(dir, "a"), image(dir, "b"), image(dir, "c")]
        let probe = QueueReaderProbe(blockFirst: true)
        let queue = MetadataLoadingQueue(maxConcurrentReads: 1, reader: { await probe.read($0) })
        queue.synchronize(images)
        await probe.waitForFirst()
        queue.prioritize(ids: [images[2].id])
        await probe.unblock()
        await finish(queue, images)
        let jobs = await probe.jobs
        #expect(jobs.count == 6)
        #expect(jobs.prefix(3).map(\.request.id) == [images[0].id, images[2].id, images[2].id])
        #expect(jobs[1].key.kind == .editable && jobs[2].key.kind == .additional)
        #expect(queue.completed == 3 && queue.failures == 0)
        #expect(queue.originalCounts[images[2].id] == 2)
        #expect(queue.hasCached(request(images[2]), kind: .editable))
        queue.synchronize(images)
        await finish(queue, images)
        #expect(await probe.jobs.count == 6)
        queue.refresh(ids: [images[2].id])
        #expect(!queue.hasCached(request(images[2]), kind: .editable))
        await finish(queue, [images[2]])
        #expect(await probe.jobs.count == 8)
    }
    @Test func changedFileDiscardsInFlightResultAndRequeuesLatestVersion() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = try image(dir, "changed")
        let probe = QueueReaderProbe(blockFirst: true)
        let queue = MetadataLoadingQueue(maxConcurrentReads: 1, reader: { await probe.read($0) })
        queue.synchronize([image])
        await probe.waitForFirst()
        try Data("a different size".utf8).write(to: image.metadataInspectionURL!)
        await probe.unblock()
        await finish(queue, [image])
        // The consumer of the old version is allowed to receive nil; the retry resolves the new version.
        await finish(queue, [image])
        #expect(queue.statuses[image.id] == .ready)
        #expect(await probe.jobs.filter { $0.key.kind == .editable }.count == 2)
    }
    @Test func failureCompletesProgressAndRemovalDoesNotReviveOldRows() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = try image(dir, "failed")
        let failure = QueueReaderProbe(fail: true)
        let queue = MetadataLoadingQueue(maxConcurrentReads: 1, reader: { await failure.read($0) })
        queue.synchronize([image])
        await finish(queue, [image])
        #expect(queue.completed == 1 && queue.failures == 1)
        #expect(queue.originalCounts[image.id] == nil)
        queue.synchronize([])
        #expect(queue.total == 0 && queue.statuses.isEmpty)

        let blocked = QueueReaderProbe(blockFirst: true)
        let removed = MetadataLoadingQueue(maxConcurrentReads: 1, reader: { await blocked.read($0) })
        removed.synchronize([image])
        await blocked.waitForFirst()
        removed.synchronize([])
        await blocked.unblock()
        #expect(await removed.read(request(image), kind: .editable) == nil)
        #expect(removed.statuses.isEmpty)
    }
    @Test func realJPEGReadAndDraftCountsUseSavedBaseline() async throws {
        let source = try #require(Bundle.main.url(forResource: "P1000658", withExtension: "JPG"))
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("real.jpg")
        try FileManager.default.copyItem(at: source, to: url)
        var image = ImageData(metadata: Metadata(source: .image(url)), name: "real.jpg")
        let queue = MetadataLoadingQueue()
        queue.synchronize([image])
        let core = await queue.read(request(image), kind: .editable)
        guard case .editable(let snapshot, let legacy) = core else { Issue.record("Real typed read failed"); return }
        guard case .display(let values) = await queue.read(request(image), kind: .additional) else {
            Issue.record("Real full read failed"); return
        }
        #expect(snapshot.requestedTags == Set(MetadataTag.allCases))
        #expect(legacy == (try Exiftool.helper.legacyCreatorTags(from: url)))
        #expect(queue.statuses[image.id] == .ready)
        #expect(queue.originalCounts[image.id] == MetadataLoadingQueue.originalCount(values))
        #expect(queue.editedCount(image) == 0)
        let plan = try MetadataCreatorEditPlan.prepare([(image, snapshot)], tag: .titleDefault,
                                                       action: .setText("Queue draft test"))
        image.applyMetadataDraft(try #require(plan.items.first))
        #expect(queue.editedCount(image) == 1)
        image.creatorDraft = nil
        #expect(queue.editedCount(image) == 0)
        image.metadata.dateTimeCreated = "2024:01:01 00:00:00"
        image.metadata.city = "Test city"
        #expect(queue.editedCount(image) == 2)
        image.metadata = try #require(image.original)
        #expect(queue.editedCount(image) == 0)
    }
    @Test func savingPausesWaitingReadsWithoutCancellingActiveRead() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let images = try [image(dir, "a"), image(dir, "b")]
        let probe = QueueReaderProbe(blockFirst: true)
        let queue = MetadataLoadingQueue(maxConcurrentReads: 1, reader: { await probe.read($0) })
        queue.setPaused(true)
        queue.synchronize(images)
        await Task.yield()
        #expect(await probe.jobs.isEmpty)
        queue.setPaused(false)
        await probe.waitForFirst()
        queue.setPaused(true)
        await probe.unblock()
        _ = await queue.read(request(images[0]), kind: .editable)
        #expect(await probe.jobs.count == 1)
        #expect(queue.hasCached(request(images[0]), kind: .editable))
        queue.setPaused(false)
        await finish(queue, images)
        #expect(await probe.jobs.count == 4)
        #expect(queue.completed == 2)
    }

    @Test func originalTagsExcludeFileAndDerivedFields() {
        #expect(MetadataLoadingQueue.originalCount([
            "File:FileName": "a", "System:FileModifyDate": "date", "Composite:GPSPosition": "0",
            "ExifTool:ExifToolVersion": "13.45", "Canon:ISO": "100", "Canon:Copy1:ISO": "200",
            "ExifIFD:ISO": "100", "IPTC:Keywords": "[a,b]", "XMP-dc:Subject": "[c,d]",
            "Image/IFD0:Make": "camera", "Image/File:FileSize": "1"
        ]) == 6)
    }
}
