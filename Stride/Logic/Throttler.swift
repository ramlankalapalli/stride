import Foundation

// Foundation-hardening pass — Phase 1.0.5.
//
// AppState.applyLiveSteps used to call persist() (a full JSON re-encode of
// the entire app state) and publishToWidget() on every single raw
// CMPedometer delta — unbounded frequency while walking, all disk I/O, no
// batching. This coalesces frequent calls into at most one write per
// `interval`, with a trailing call so the final state is never silently
// dropped, plus a `flushNow` escape hatch for moments that must never be
// delayed (goal crossings, purchases, backgrounding).

final class Throttler {
    private let interval: TimeInterval
    private let queue: DispatchQueue
    private var lastFired: Date?
    private var pendingWorkItem: DispatchWorkItem?

    init(interval: TimeInterval, queue: DispatchQueue = .main) {
        self.interval = interval
        self.queue = queue
    }

    /// Runs `action` immediately if outside the cooldown window; otherwise
    /// schedules exactly one trailing call so the latest state still lands.
    func call(_ action: @escaping () -> Void) {
        pendingWorkItem?.cancel()
        let now = Date()
        if let last = lastFired, now.timeIntervalSince(last) < interval {
            let item = DispatchWorkItem { [weak self] in
                self?.lastFired = Date()
                action()
            }
            pendingWorkItem = item
            queue.asyncAfter(deadline: .now() + (interval - now.timeIntervalSince(last)), execute: item)
        } else {
            lastFired = now
            action()
        }
    }

    /// Cancels any pending trailing call and runs `action` right now —
    /// for events that must never be delayed by the cooldown window.
    func flushNow(_ action: () -> Void) {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        lastFired = Date()
        action()
    }
}
