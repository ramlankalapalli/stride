import Foundation

// Streak rules. Handoff §5.
//
// A day is "hit" if automatic steps (phone + watch) >= dailyGoal by local
// midnight — automatic-only, the same rule goal completion, milestones, and
// the leaderboard all share. `current` increments at midnight rollover when
// the completed day was a hit, and resets to 0 on a miss. `best` is kept
// permanently, even after a reset — it is what the copy uses to say what
// was thrown away.

enum StreakEngine {

    /// Delegates to CreditedSteps rather than comparing the raw total
    /// directly — a day only "hits" on its automatic total. This matters
    /// for old records that may still carry a legacy manual value; new
    /// records never have one, so this is equivalent to a plain total
    /// comparison for anything created after manual entry was removed.
    static func isHit(_ record: DailyRecord, goal: Int) -> Bool {
        CreditedSteps.qualifies(record, goal: goal)
    }

    /// Fold a completed day into the streak. Call once at midnight rollover,
    /// and on launch for every local day missed while the app was closed.
    static func rollOver(_ streak: Streak, completed: DailyRecord, goal: Int) -> Streak {
        var s = streak
        s.totalDaysTracked += 1

        if isHit(completed, goal: goal) {
            s.current += 1
            s.totalDaysHit += 1
            s.best = max(s.best, s.current)
        } else {
            s.current = 0
            s.totalDaysMissed += 1
        }
        return s
    }

    /// Days with no record at all are misses. Closing the app does not pause
    /// the record.
    static func rollOverMissingDay(_ streak: Streak) -> Streak {
        var s = streak
        s.totalDaysTracked += 1
        s.totalDaysMissed += 1
        s.current = 0
        return s
    }

    /// Phase 1.0.5 — fixes the same-day display lag: previously
    /// AppState.creditGoalDay computed a provisional streak for the
    /// milestone check but never wrote it back, so the persisted
    /// `streak.current` only ever updated the *next* time `reconcile` ran —
    /// meaning Home/Record/Profile kept showing yesterday's count even after
    /// today's goal was legitimately hit.
    ///
    /// This is a pure, read-only projection: it never mutates the persisted
    /// streak, so `reconcile`'s day-by-day walk (which only ever processes
    /// days strictly before "today" at the time it runs) is completely
    /// unaffected and cannot double-count. The day that was "today" when
    /// this projected a +1 gets folded into the real, persisted streak
    /// exactly once, on the first `reconcile` call where it has become a
    /// genuinely completed past day — same as before this existed.
    static func displayedStreak(base: Streak, todayQualifies: Bool) -> Streak {
        guard todayQualifies else { return base }
        var projected = base
        projected.current += 1
        projected.best = max(projected.best, projected.current)
        return projected
    }

    /// Catch up the streak from the last processed day to yesterday.
    static func reconcile(streak: Streak,
                          lastProcessed: Date?,
                          records: [Date: DailyRecord],
                          goal: Int,
                          calendar: Calendar = .current,
                          now: Date = Date()) -> (streak: Streak, lastProcessed: Date) {
        let today = calendar.startOfDay(for: now)
        guard var cursor = lastProcessed.map({ calendar.startOfDay(for: $0) }) else {
            return (streak, today)
        }

        var s = streak
        while let next = calendar.date(byAdding: .day, value: 1, to: cursor), next < today {
            if let record = records[next] {
                s = rollOver(s, completed: record, goal: goal)
            } else {
                s = rollOverMissingDay(s)
            }
            cursor = next
        }
        return (s, today)
    }
}

// MARK: - Milestones

// Handoff §5: fire the Milestone screen on every 7-day multiple, on a new
// personal best, and on the first goal-day ever.

enum Milestones {
    /// Identifiable conformance (RootView.swift) drives the fullScreenCover
    /// that presents MilestoneScreen. Hashable is kept for value-semantics
    /// equality checks generally, though it's no longer required by Route
    /// specifically — see the note on Route.swift's removed .milestone case.
    struct Event: Hashable {
        var streak: Int
        var isPersonalBest: Bool
        var isFirstEver: Bool
    }

    static func event(after streak: Streak, previousBest: Int, isFirstGoalDayEver: Bool) -> Event? {
        let isBest = streak.current > previousBest && streak.current > 1
        let isSeven = streak.current > 0 && streak.current % 7 == 0

        guard isFirstGoalDayEver || isBest || isSeven else { return nil }
        return Event(streak: streak.current,
                     isPersonalBest: isBest,
                     isFirstEver: isFirstGoalDayEver)
    }
}
