import Foundation

// Points. Handoff §5.
//
// TODO(open): §9 lists the formula as unconfirmed. These are the §5 suggested
// values, applied as defaults. Change them here and nothing else moves.

enum Points {
    static let perGoalDay = 100
    static let weeklyChallengeBonus = 50

    /// Manual entries can't be farmed for unlocks. Only this share of the daily
    /// goal counts toward points, however much gets typed in.
    static let manualContributionCap = 0.20

    /// Points earned for one day's record.
    static func award(for record: DailyRecord, goal: Int) -> Int {
        guard goal > 0 else { return 0 }
        let manualAllowed = Int(Double(goal) * manualContributionCap)
        let countedManual = min(record.stepsManualAdd, manualAllowed)
        let counted = record.automatic + countedManual
        return counted >= goal ? perGoalDay : 0
    }

    /// Steps that count toward the points award, after the manual cap.
    /// The record itself still shows the true total — the cap only limits points.
    static func countedTowardPoints(_ record: DailyRecord, goal: Int) -> Int {
        let manualAllowed = Int(Double(goal) * manualContributionCap)
        return record.automatic + min(record.stepsManualAdd, manualAllowed)
    }

    static func award(for challenge: WeeklyChallenge) -> Int {
        challenge.daysHit >= challenge.target ? weeklyChallengeBonus : 0
    }
}
