import Foundation

/// Decisions are independent of Bluetooth and timers, so cancellation, sleep,
/// backoff, and user intent can be verified without touching a real microphone.
struct ReconnectPolicy {
    var enabled = true
    var target: UUID?
    var userPaused = false
    var suspended = false
    var available = true
    var connecting = false
    var connected = false
    private(set) var failures = 0

    var canAttempt: Bool {
        enabled && target != nil && !userPaused && !suspended && available && !connecting && !connected
    }
    mutating func beginAttempt() -> UUID? {
        guard canAttempt else { return nil }
        connecting = true
        return target
    }
    mutating func manualAttempt() {
        userPaused = false; connecting = true; connected = false
    }
    mutating func succeeded(_ id: UUID) {
        target = id; connecting = false; connected = true; failures = 0; userPaused = false
    }
    mutating func connectionEnded() { connecting = false; connected = false }
    mutating func failed(retryable: Bool) -> TimeInterval? {
        connectionEnded()
        if !retryable { userPaused = true; return nil }
        guard canAttempt else { return nil }
        failures = min(failures + 1, 6)
        return min(30, pow(2, Double(failures - 1)))
    }
    mutating func pause() { userPaused = true; connectionEnded() }
    mutating func resume() { userPaused = false; failures = 0 }
}
