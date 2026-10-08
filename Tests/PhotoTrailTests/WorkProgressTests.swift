import Testing
@testable import PhotoTrail

struct WorkProgressTests {
    @Test func estimateRequiresSamplesAndFollowsThroughput() throws {
        var estimate = RemainingTimeEstimate()
        estimate.reset(now: 0)
        estimate.update(completed: 4, now: 2)
        #expect(estimate.seconds(total: 100) == nil)
        estimate.update(completed: 12, now: 6)
        #expect(estimate.seconds(total: 100) == 44)
        for index in 1...40 { estimate.update(completed: 12 + index * 2, now: 6 + Double(index)) }
        #expect(estimate.seconds(total: 100) == 4)
        estimate.update(completed: 100, now: 50)
        #expect(estimate.seconds(total: 100) == nil)
        estimate.reset(completed: 100, now: 100)
        #expect(estimate.seconds(total: 200) == nil)
    }
    @Test func fastUpdatesStillProduceAnEstimateAndInvalidationResetsIt() {
        var estimate = RemainingTimeEstimate()
        estimate.reset(now: 0)
        for index in 1...1000 { estimate.update(completed: index, now: Double(index) / 100) }
        #expect(estimate.seconds(total: 2000) != nil)
        estimate.update(completed: 0, now: 11)
        #expect(estimate.seconds(total: 2000) == nil)
    }
}

extension WorkProgressTests {
    @Test @MainActor func overallImportIncludesUnreadMetadataAndUnknownFutureStages() {
        let metadata = MetadataLoadingQueue.ReadProgress()
        metadata.total = 20
        metadata.resetTiming(now: 0)
        metadata.editableRead = 4
        metadata.updateTiming(now: 2)
        metadata.editableRead = 12
        metadata.updateTiming(now: 6)
        #expect(metadata.overallRemainingSeconds == nil)
        metadata.editableRead = 20
        metadata.updateTiming(now: 10)
        metadata.displayRead = 4
        metadata.updateTiming(now: 12)
        metadata.displayRead = 12
        metadata.updateTiming(now: 16)
        #expect(metadata.overallRemainingSeconds == 4)
        #expect(metadata.estimatedSeconds(forPhotos: 30) == 30)
        let importing = ImportProgress()
        importing.begin(.images, total: 30)
        importing.completed = 10
        importing.remainingSeconds = 20
        #expect(importing.overallRemainingSeconds(metadataSeconds: nil) == nil)
        #expect(importing.overallRemainingSeconds(metadataSeconds: metadata.estimatedSeconds(forPhotos: 30)) == 50)
        importing.completed = 30
        #expect(importing.overallRemainingSeconds(metadataSeconds: 30) == 30)
        importing.pendingTracks = true
        #expect(importing.overallRemainingSeconds(metadataSeconds: 30) == nil)
        metadata.displayRead = 20
        metadata.updateTiming(now: 20)
        #expect(metadata.overallRemainingSeconds == 0)
    }
}
