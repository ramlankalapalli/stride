import Foundation

// Streak rules. Handoff §5.
//
// A day is "hit" if phone + watch + manual >= dailyGoal by local midnight.
// `current` increments at midnight rollover when the completed day was a hit,
// and resets to 0 on a miss. `best` is kept permanently, even after a reset —
// it is what the copy uses to say what was thrown away.

enum StreakEngine {

    static func isHit(_ record: DailyRecord, goal: Int) -> Bool {
        record.total >= goal
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
    /// Hashable (not just Equatable) — Route embeds this in an enum case and
    /// Route itself needs to stay Hashable for NavigationStack's path.
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
