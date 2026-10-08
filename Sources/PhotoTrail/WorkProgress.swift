import Foundation
import Observation

/// A short completion window follows changing throughput without a fixed machine benchmark.
struct RemainingTimeEstimate {
    private var started = false
    private var samples: [(time: Double, completed: Int)] = []
    mutating func reset(completed: Int = 0, now: Double = ProcessInfo.processInfo.systemUptime) {
        samples = [(now, completed)]
        started = false
    }
    mutating func update(completed: Int, now: Double = ProcessInfo.processInfo.systemUptime) {
        guard let last = samples.last, last.completed != completed else { return }
        if completed < last.completed { reset(completed: completed, now: now); return }
        // Queue wait and preceding phases are not samples of this stage's throughput.
        if !started {
            samples = [(now, completed)]
            started = true
            return
        }
        guard now - last.time >= 0.25 else { return }
        samples.append((now, completed))
        if samples.count > 32 { samples.removeFirst(samples.count - 32) }
    }
    var secondsPerUnit: Double? {
        guard let first = samples.first, let last = samples.last,
              last.completed - first.completed >= 8, last.time - first.time >= 3 else { return nil }
        return (last.time - first.time) / Double(last.completed - first.completed)
    }
    func seconds(total: Int) -> Double? {
        guard let last = samples.last, last.completed < total, let rate = secondsPerUnit else { return nil }
        return Double(total - last.completed) * rate
    }
}

@Observable @MainActor final class ImportProgress {
    nonisolated init() {}
    enum Phase { case scanning, images, tracks }
    var isActive = false
    var preparesPhotoMetadata = false
    var photoCount = 0
    var pendingTracks = false
    var phase: Phase = .scanning
    var completed = 0
    var total = 0
    var remainingSeconds: Double?
    @ObservationIgnored private var estimate = RemainingTimeEstimate()

    func begin(_ phase: Phase, total: Int = 0) {
        if phase == .scanning { preparesPhotoMetadata = false; photoCount = 0 }
        if phase == .images { preparesPhotoMetadata = total >= 100; photoCount = total }
        self.phase = phase
        self.total = total
        completed = 0
        remainingSeconds = nil
        estimate.reset()
        isActive = true
    }
    func update(completed: Int) {
        self.completed = completed
        estimate.update(completed: completed)
        remainingSeconds = estimate.seconds(total: total)
    }
    func overallRemainingSeconds(metadataSeconds: Double?) -> Double? {
        guard phase != .scanning, !pendingTracks else { return nil }
        let base = completed >= total ? 0 : remainingSeconds
        guard let base else { return nil }
        guard photoCount > 0 else { return base }
        return metadataSeconds.map { base + $0 }
    }
    func finish() { isActive = false; remainingSeconds = nil }
}
