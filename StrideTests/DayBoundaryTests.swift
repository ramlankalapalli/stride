import XCTest
@testable import Stride

final class DayBoundaryTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func test_startOfDay_truncatesToMidnight() {
        let cal = calendar
        let date = cal.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 14, minute: 30))!
        let start = DayBoundary.startOfDay(date, calendar: cal)
        let comps = cal.dateComponents([.hour, .minute, .second], from: start)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertEqual(comps.second, 0)
    }

    func test_hasRolledOver_sameDay_isFalse() {
        let cal = calendar
        let morning = cal.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 1))!
        let evening = cal.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 23))!
        XCTAssertFalse(DayBoundary.hasRolledOver(from: morning, now: evening, calendar: cal))
    }

    func test_hasRolledOver_nextDay_isTrue() {
        let cal = calendar
        let day1 = cal.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 23, minute: 59))!
        let day2 = cal.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 0, minute: 1))!
        XCTAssertTrue(DayBoundary.hasRolledOver(from: day1, now: day2, calendar: cal))
    }

    func test_hasRolledOver_normalizesPreviousStart_notJustExactMidnight() {
        // previousDayStart doesn't have to already be exactly midnight — the
        // function normalizes it too, so passing "yesterday at 3pm" as the
        // reference still correctly detects today as a new day. This matters
        // because StepProvider always passes an actual startOfDay value, but
        // the helper itself shouldn't silently depend on that.
        let cal = calendar
        let yesterdayAfternoon = cal.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 15))!
        let today = cal.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 0, minute: 30))!
        XCTAssertTrue(DayBoundary.hasRolledOver(from: yesterdayAfternoon, now: today, calendar: cal))
    }

    func test_nextMidnight_isStartOfFollowingDay() {
        let cal = calendar
        let date = cal.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 14, minute: 30))!
        let next = DayBoundary.nextMidnight(after: date, calendar: cal)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: next)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 6)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
    }

    func test_nextMidnight_crossesMonthBoundary() {
        let cal = calendar
        let date = cal.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 10))!
        let next = DayBoundary.nextMidnight(after: date, calendar: cal)
        let comps = cal.dateComponents([.year, .month, .day], from: next)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 1)
    }

    func test_nextMidnight_crossesYearBoundary() {
        let cal = calendar
        let newYearsEve = cal.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23, minute: 30))!
        let next = DayBoundary.nextMidnight(after: newYearsEve, calendar: cal)
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: next)
        XCTAssertEqual(comps.year, 2027)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 1)
        XCTAssertEqual(comps.hour, 0)
    }

    func test_hasRolledOver_acrossYearBoundary() {
        let cal = calendar
        let dec31 = cal.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23, minute: 59))!
        let jan1 = cal.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 0, minute: 1))!
        XCTAssertTrue(DayBoundary.hasRolledOver(from: dec31, now: jan1, calendar: cal))
    }
}
