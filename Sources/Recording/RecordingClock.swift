import Foundation

struct RecordingClock {
    let started: TimeInterval
    private var pausedAt: TimeInterval?
    private var pausedDuration: TimeInterval = 0
    init(started: TimeInterval = ProcessInfo.processInfo.systemUptime) { self.started = started }
    func elapsed(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        max(0, (pausedAt ?? now) - started - pausedDuration)
    }
    mutating func pause(now: TimeInterval = ProcessInfo.processInfo.systemUptime) { if pausedAt == nil { pausedAt = now } }
    mutating func resume(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if let pausedAt { pausedDuration += now - pausedAt }
        pausedAt = nil
    }
}
