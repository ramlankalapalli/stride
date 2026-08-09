import Foundation

// Foundation-hardening pass — Phase 1.0.5.
//
// Pure local-day-boundary logic, deliberately kept free of CoreMotion,
// SwiftUI, and StepProvider so it's unit-testable without any of them.
// StepProvider uses this to detect a local midnight rollover while the app
// stays alive and to schedule a proactive rebase at the next midnight,
// instead of only ever re-deriving "today" at cold launch.

enum DayBoundary {

    /// `Calendar.current.startOfDay(for:)`, pulled out to one call site so
    /// every rollover check agrees on the same definition of "today".
    static func startOfDay(_ date: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// True once `now` has crossed into a different local day than
    /// `previousDayStart`. Deliberately takes `previousDayStart` (not a
    /// last-checked timestamp) so the caller's own state IS the day being
    /// compared against — no separate bookkeeping to drift out of sync.
    static func hasRolledOver(from previousDayStart: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        startOfDay(now, calendar: calendar) != startOfDay(previousDayStart, calendar: calendar)
    }

    /// The next local midnight strictly after `date` — for scheduling a
    /// proactive rebase rather than only catching rollover on the next
    /// timer tick or pedometer delta.
    static func nextMidnight(after date: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = startOfDay(date, calendar: calendar)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
    }
}
