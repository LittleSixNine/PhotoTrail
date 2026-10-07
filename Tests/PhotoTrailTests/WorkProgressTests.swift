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
