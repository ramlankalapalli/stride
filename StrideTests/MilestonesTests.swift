import XCTest
@testable import Stride

final class MilestonesTests: XCTestCase {

    func test_firstGoalDayEver_firesEvent() {
        let streak = Streak(current: 1, best: 1)
        let event = Milestones.event(after: streak, previousBest: 0, isFirstGoalDayEver: true)
        XCTAssertNotNil(event)
        XCTAssertTrue(event?.isFirstEver ?? false)
    }

    func test_newPersonalBest_firesEvent() {
        let streak = Streak(current: 6, best: 6)
        let event = Milestones.event(after: streak, previousBest: 5, isFirstGoalDayEver: false)
        XCTAssertNotNil(event)
        XCTAssertTrue(event?.isPersonalBest ?? false)
    }

    func test_sevenDayMultiple_firesEvent() {
        // Not a best (best is already ahead), but a multiple of 7.
        let streak = Streak(current: 14, best: 20)
        let event = Milestones.event(after: streak, previousBest: 20, isFirstGoalDayEver: false)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.streak, 14)
        XCTAssertFalse(event?.isPersonalBest ?? true)
    }

    func test_ordinaryDay_noEvent() {
        // Day 4: not a best, not a multiple of 7, not the first ever.
        let streak = Streak(current: 4, best: 10)
        let event = Milestones.event(after: streak, previousBest: 10, isFirstGoalDayEver: false)
        XCTAssertNil(event)
    }

    func test_dayOne_notFlaggedFirstEver_doesNotFalselyFireAsBest() {
        // Guards day one (current=1) against being misclassified as a "new
        // best" purely from crossing previousBest=0 — event() requires
        // current > 1 for the best-check specifically, so an un-flagged day
        // one correctly produces no event at all (isFirstGoalDayEver is the
        // only thing meant to announce day one).
        let streak = Streak(current: 1, best: 1)
        let event = Milestones.event(after: streak, previousBest: 0, isFirstGoalDayEver: false)
        XCTAssertNil(event)
    }

    func test_streakBrokenThenRestarted_previousBestStillGuardsFalsePositive() {
        // current(1) > previousBest(0) alone isn't enough — same guard as
        // above, exercised via a "streak just reset then hit day one again"
        // shape rather than a fresh account.
        let streak = Streak(current: 1, best: 8)
        let event = Milestones.event(after: streak, previousBest: 8, isFirstGoalDayEver: false)
        XCTAssertNil(event)
    }
}
