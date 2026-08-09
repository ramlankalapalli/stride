import XCTest
@testable import Stride

/// Stride is an automatic-movement product — manual step entry has been
/// removed from the experience (see AppState, TrackingScreens).
/// CreditedSteps.qualifies is now a pure automatic-total check. These tests
/// also cover the migration guarantee: DailyRecord.stepsManualAdd may still
/// be nonzero on records persisted before the removal, and must never count
/// toward qualification, no matter how large.
final class CreditedStepsTests: XCTestCase {

    private func record(automatic: Int = 0, legacyManual: Int = 0) -> DailyRecord {
        var r = DailyRecord(date: Date())
        r.stepsFromPhone = automatic
        r.stepsManualAdd = legacyManual
        return r
    }

    // MARK: - Automatic-only qualification (current product model)

    func test_qualifies_exactlyAtGoal() {
        XCTAssertTrue(CreditedSteps.qualifies(record(automatic: 6000), goal: 6000))
    }

    func test_qualifies_oneShortOfGoal() {
        XCTAssertFalse(CreditedSteps.qualifies(record(automatic: 5999), goal: 6000))
    }

    func test_zeroGoal_neverQualifies() {
        XCTAssertFalse(CreditedSteps.qualifies(record(automatic: 100), goal: 0))
    }

    func test_zeroAutomatic_neverQualifies() {
        XCTAssertFalse(CreditedSteps.qualifies(record(automatic: 0), goal: 6000))
    }

    // MARK: - Legacy migration: old manual values never qualify, at any size

    func test_legacyManualAlone_neverQualifies_evenAtExactGoalValue() {
        // Pre-migration record: someone typed in exactly the goal, no
        // automatic steps at all. Must not qualify — automatic is the only
        // source that ever counts, retroactively as well as going forward.
        let r = record(automatic: 0, legacyManual: 6000)
        XCTAssertFalse(CreditedSteps.qualifies(r, goal: 6000))
    }

    func test_legacyManualAlone_neverQualifies_evenWhenMassivelyOverGoal() {
        // No cap math anymore — it's a hard exclusion, not a percentage.
        let r = record(automatic: 0, legacyManual: 100_000)
        XCTAssertFalse(CreditedSteps.qualifies(r, goal: 6000))
    }

    func test_automaticAlone_qualifiesRegardlessOfLegacyManualPresent() {
        // A legacy record that happens to ALSO have real automatic steps —
        // the automatic portion alone must still correctly qualify,
        // completely unaffected by whatever manual value sits alongside it.
        let r = record(automatic: 6000, legacyManual: 500)
        XCTAssertTrue(CreditedSteps.qualifies(r, goal: 6000))
    }

    func test_automaticJustUnderGoal_legacyManualCannotTopItUp() {
        // The previous (Phase 1.0.5) model let a capped slice of manual
        // entry help close the gap. The current automatic-only model
        // doesn't — automatic must clear the goal entirely on its own.
        let r = record(automatic: 5900, legacyManual: 500)
        XCTAssertFalse(CreditedSteps.qualifies(r, goal: 6000))
    }

    // MARK: - Raw total is unaffected — historical display stays honest

    func test_rawTotalStillIncludesLegacyManual_qualificationDoesNot() {
        let r = record(automatic: 500, legacyManual: 10_000)
        XCTAssertEqual(r.total, 10_500) // .total is unchanged — historical display stays honest
        XCTAssertFalse(CreditedSteps.qualifies(r, goal: 6000)) // qualification ignores it entirely
    }

    func test_newRecordHasNoManualByConstruction() {
        // Nothing in the app can write stepsManualAdd anymore
        // (AppState.addManualSteps was removed). A freshly-created record
        // always starts at 0, so raw and automatic totals are identical.
        let r = DailyRecord(date: Date())
        XCTAssertEqual(r.stepsManualAdd, 0)
        XCTAssertEqual(r.total, r.automatic)
    }
}
