import Foundation

// Points. Handoff §5.
//
// TODO(open): §9 lists the formula as unconfirmed. These are the §5 suggested
// values, applied as defaults. Change them here and nothing else moves.
//
// Automatic-only product decision: qualification delegates entirely to
// CreditedSteps.qualifies, which checks a record's automatic total —
// nothing else. Manual entry no longer exists going forward; CreditedSteps
// still guards against a legacy record's old manual value counting here.

enum Points {
    static let perGoalDay = 100

    /// Deferred, not wired — see the comment on `award(for: WeeklyChallenge)`
    /// below.
    static let weeklyChallengeBonus = 50

    /// Points earned for one day's record. Same qualification rule as goal
    /// completion, streaks, and the leaderboard — see CreditedSteps.
    static func award(for record: DailyRecord, goal: Int) -> Int {
        CreditedSteps.qualifies(record, goal: goal) ? perGoalDay : 0
    }

    /// Exists but is intentionally never called. Wiring a first-time weekly
    /// bonus needs its own idempotency state (something durable tracking
    /// "already paid out for week of X" that survives relaunch) and no UI
    /// currently promises this amount to the user anywhere — WeeklyChallengeScreen
    /// shows progress only, no point value. Rather than add new persisted
    /// reward state in a hardening pass, this is left as documented-and-
    /// deferred: a future phase decides whether/how weekly bonuses ship,
    /// wires the idempotency, and only then calls this.
    static func award(for challenge: WeeklyChallenge) -> Int {
        challenge.daysHit >= challenge.target ? weeklyChallengeBonus : 0
    }
}
