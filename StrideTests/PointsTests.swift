import XCTest
@testable import Stride

final class PointsTests: XCTestCase {

    private func record(automatic: Int = 0, legacyManual: Int = 0) -> DailyRecord {
        var r = DailyRecord(date: Date())
        r.stepsFromPhone = automatic
        r.stepsManualAdd = legacyManual
        return r
    }

    func test_award_qualifyingDay_earnsPerGoalDay() {
        XCTAssertEqual(Points.award(for: record(automatic: 6000), goal: 6000), Points.perGoalDay)
    }

    func test_award_nonQualifyingDay_earnsNothing() {
        XCTAssertEqual(Points.award(for: record(automatic: 3000), goal: 6000), 0)
    }

    func test_award_ignoresLegacyManualEntirely() {
        // A pre-migration record with a large manual value must not earn
        // points off that value — automatic is the sole authority for
        // rewards, past records included.
        let r = record(automatic: 0, legacyManual: 6000)
        XCTAssertGreaterThanOrEqual(r.total, 6000) // raw total clears the goal
        XCTAssertEqual(Points.award(for: r, goal: 6000), 0) // award does not
    }

    /// "No duplicate reward" at this layer means award() is a pure function
    /// of the record's state, not of history — the same qualifying record
    /// always returns the same amount. AppState is what actually prevents a
    /// double *credit* to the user's balance (the wasMet/newlyQualified
    /// edge-trigger in applyLiveSteps) — this confirms the pure building
    /// block it depends on is itself deterministic.
    func test_award_isDeterministic_repeatedCallsAgree() {
        let r = record(automatic: 6000)
        XCTAssertEqual(Points.award(for: r, goal: 6000), Points.award(for: r, goal: 6000))
    }

    /// Documents current, intentional behavior: the weekly bonus formula is
    /// correct and callable, but deliberately left unwired — see the
    /// comment on Points.award(for: WeeklyChallenge).
    func test_weeklyBonus_computesCorrectly_thoughCurrentlyUnwired() {
        let hit = WeeklyChallenge(weekStart: Date(), target: 5, daysHit: 5)
        let short = WeeklyChallenge(weekStart: Date(), target: 5, daysHit: 4)
        XCTAssertEqual(Points.award(for: hit), Points.weeklyChallengeBonus)
        XCTAssertEqual(Points.award(for: short), 0)
    }
}
