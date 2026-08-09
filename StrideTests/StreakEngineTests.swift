import XCTest
@testable import Stride

final class StreakEngineTests: XCTestCase {

    private func record(total: Int, date: Date = Date()) -> DailyRecord {
        var r = DailyRecord(date: date)
        r.stepsFromPhone = total
        return r
    }

    // MARK: - rollOver

    func test_rollOver_firstHit() {
        let result = StreakEngine.rollOver(Streak(), completed: record(total: 6000), goal: 6000)
        XCTAssertEqual(result.current, 1)
        XCTAssertEqual(result.best, 1)
        XCTAssertEqual(result.totalDaysHit, 1)
        XCTAssertEqual(result.totalDaysTracked, 1)
        XCTAssertEqual(result.totalDaysMissed, 0)
    }

    func test_rollOver_consecutiveHits() {
        var streak = Streak()
        for _ in 0..<5 {
            streak = StreakEngine.rollOver(streak, completed: record(total: 6000), goal: 6000)
        }
        XCTAssertEqual(streak.current, 5)
        XCTAssertEqual(streak.best, 5)
        XCTAssertEqual(streak.totalDaysHit, 5)
    }

    func test_rollOver_miss_resetsCurrentButKeepsBest() {
        var streak = Streak()
        streak = StreakEngine.rollOver(streak, completed: record(total: 6000), goal: 6000)
        streak = StreakEngine.rollOver(streak, completed: record(total: 6000), goal: 6000)
        XCTAssertEqual(streak.current, 2)

        streak = StreakEngine.rollOver(streak, completed: record(total: 1000), goal: 6000) // miss
        XCTAssertEqual(streak.current, 0)
        XCTAssertEqual(streak.best, 2) // kept, per the "you threw it away" copy
        XCTAssertEqual(streak.totalDaysMissed, 1)
    }

    func test_rollOverMissingDay_countsAsMiss() {
        let streak = StreakEngine.rollOverMissingDay(Streak(current: 3, best: 3))
        XCTAssertEqual(streak.current, 0)
        XCTAssertEqual(streak.best, 3)
        XCTAssertEqual(streak.totalDaysMissed, 1)
        XCTAssertEqual(streak.totalDaysTracked, 1)
    }

    // MARK: - reconcile

    func test_reconcile_foldsCompletedDaysAndAdvancesLastProcessed() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!

        var records: [Date: DailyRecord] = [:]
        records[twoDaysAgo] = record(total: 6000, date: twoDaysAgo)
        records[yesterday] = record(total: 6000, date: yesterday)

        let result = StreakEngine.reconcile(streak: Streak(),
                                            lastProcessed: cal.date(byAdding: .day, value: -3, to: today),
                                            records: records, goal: 6000,
                                            calendar: cal, now: today)
        XCTAssertEqual(result.streak.current, 2)
        XCTAssertEqual(result.streak.totalDaysTracked, 2)
        XCTAssertTrue(cal.isDate(result.lastProcessed, inSameDayAs: today))
    }

    func test_reconcile_missingDayBreaksStreak() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let result = StreakEngine.reconcile(
            streak: Streak(current: 4, best: 4, totalDaysTracked: 4, totalDaysHit: 4),
            lastProcessed: cal.date(byAdding: .day, value: -2, to: today),
            records: [:], // no record for yesterday at all
            goal: 6000, calendar: cal, now: today)
        XCTAssertEqual(result.streak.current, 0)
        XCTAssertEqual(result.streak.best, 4)
    }

    func test_reconcile_neverTouchesToday() {
        // reconcile only walks up to (but not including) "now"'s day —
        // this is the invariant displayedStreak relies on to avoid
        // double-counting.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var records: [Date: DailyRecord] = [:]
        records[today] = record(total: 6000, date: today) // today already qualifies

        let result = StreakEngine.reconcile(streak: Streak(),
                                            lastProcessed: cal.date(byAdding: .day, value: -1, to: today),
                                            records: records, goal: 6000,
                                            calendar: cal, now: today)
        XCTAssertEqual(result.streak.current, 0) // today not folded in yet
        XCTAssertTrue(cal.isDate(result.lastProcessed, inSameDayAs: today))
    }

    // MARK: - displayedStreak (same-day display fix)

    func test_displayedStreak_todayNotQualified_showsBaseUnchanged() {
        let base = Streak(current: 3, best: 5)
        let displayed = StreakEngine.displayedStreak(base: base, todayQualifies: false)
        XCTAssertEqual(displayed.current, 3)
        XCTAssertEqual(displayed.best, 5)
    }

    func test_displayedStreak_firstGoalDay() {
        let displayed = StreakEngine.displayedStreak(base: Streak(), todayQualifies: true)
        XCTAssertEqual(displayed.current, 1)
        XCTAssertEqual(displayed.best, 1)
    }

    func test_displayedStreak_consecutiveGoalDay_bumpsCurrentAndBest() {
        let base = Streak(current: 4, best: 4)
        let displayed = StreakEngine.displayedStreak(base: base, todayQualifies: true)
        XCTAssertEqual(displayed.current, 5)
        XCTAssertEqual(displayed.best, 5)
    }

    func test_displayedStreak_afterMissedPreviousDay_startsFromZeroBase() {
        // Yesterday was already a miss by the time today is being shown, so
        // base.current is already 0 going in.
        let base = Streak(current: 0, best: 6)
        let displayed = StreakEngine.displayedStreak(base: base, todayQualifies: true)
        XCTAssertEqual(displayed.current, 1)
        XCTAssertEqual(displayed.best, 6) // not a new best
    }

    func test_displayedStreak_neverMutatesPersistedBase() {
        let base = Streak(current: 2, best: 2)
        _ = StreakEngine.displayedStreak(base: base, todayQualifies: true)
        XCTAssertEqual(base.current, 2) // value semantics — base itself untouched
    }

    /// The scenario the fix exists for: user hits today's goal and sees the
    /// live +1 via displayedStreak. On relaunch (tomorrow), reconcile()
    /// folds that same day in for real. The two must agree exactly — no
    /// gap, no double count.
    func test_reconciliationAfterTodayWasAlreadyDisplayed_matchesWhatWasShown() {
        let cal = Calendar.current
        let dayOfGoalHit = cal.startOfDay(for: Date())
        let base = Streak(current: 4, best: 5, totalDaysTracked: 10, totalDaysHit: 8, totalDaysMissed: 2)

        let displayedDuringSession = StreakEngine.displayedStreak(base: base, todayQualifies: true)
        XCTAssertEqual(displayedDuringSession.current, 5)

        let tomorrow = cal.date(byAdding: .day, value: 1, to: dayOfGoalHit)!
        var records: [Date: DailyRecord] = [:]
        records[dayOfGoalHit] = record(total: 6000, date: dayOfGoalHit)

        let result = StreakEngine.reconcile(streak: base,
                                            lastProcessed: cal.date(byAdding: .day, value: -1, to: dayOfGoalHit),
                                            records: records, goal: 6000,
                                            calendar: cal, now: tomorrow)
        XCTAssertEqual(result.streak.current, displayedDuringSession.current)
        XCTAssertEqual(result.streak.best, displayedDuringSession.best)
    }

    // MARK: - Legacy manual-entry migration

    /// A record from before manual entry was removed, with a large manual
    /// value but no automatic steps, must not fold into the streak as a
    /// hit — even though reconcile() is exactly the code path that would
    /// have re-evaluated a backlog of old records on first launch after
    /// the migration.
    func test_reconcile_ignoresLegacyManualOnlyDay() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        var legacyDay = DailyRecord(date: yesterday)
        legacyDay.stepsFromPhone = 0
        legacyDay.stepsManualAdd = 6000 // old, pre-migration manual entry

        let result = StreakEngine.reconcile(streak: Streak(),
                                            lastProcessed: cal.date(byAdding: .day, value: -2, to: today),
                                            records: [yesterday: legacyDay], goal: 6000,
                                            calendar: cal, now: today)
        XCTAssertEqual(result.streak.current, 0)
        XCTAssertEqual(result.streak.totalDaysMissed, 1)
        XCTAssertEqual(result.streak.totalDaysHit, 0)
    }
}
