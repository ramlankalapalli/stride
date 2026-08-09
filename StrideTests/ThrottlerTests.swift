import XCTest
@testable import Stride

/// Throttler backs AppState's persistence coalescing (persistThrottled /
/// persistImmediately) — the fix for persist()/publishToWidget() firing on
/// every raw CMPedometer delta. Tested directly here since Throttler itself
/// has no CoreMotion/SwiftUI dependency.
final class ThrottlerTests: XCTestCase {

    func test_firstCall_runsImmediately() {
        let throttler = Throttler(interval: 5)
        var ran = false
        throttler.call { ran = true }
        XCTAssertTrue(ran)
    }

    func test_rapidCallsWithinInterval_coalesceToOneTrailingCall() {
        let throttler = Throttler(interval: 0.2)
        var callCount = 0
        var lastValue = 0

        throttler.call { callCount += 1; lastValue = 1 } // runs immediately (first call)
        throttler.call { callCount += 1; lastValue = 2 } // scheduled trailing
        throttler.call { callCount += 1; lastValue = 3 } // replaces the pending trailing call

        XCTAssertEqual(callCount, 1) // only the immediate first call has run so far
        XCTAssertEqual(lastValue, 1)

        let expectation = expectation(description: "trailing call fires with the latest state")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        // Exactly one trailing call fired (not two, not zero), and it
        // reflects the LATEST call's value, not an intermediate one —
        // "retains latest state" is the actual product requirement.
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(lastValue, 3)
    }

    func test_callOutsideInterval_runsImmediatelyAgain() {
        let throttler = Throttler(interval: 0.1)
        var callCount = 0
        throttler.call { callCount += 1 }
        XCTAssertEqual(callCount, 1)

        let expectation = expectation(description: "cooldown elapses")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        throttler.call { callCount += 1 }
        XCTAssertEqual(callCount, 2) // no trailing delay needed — cooldown already passed
    }

    func test_flushNow_cancelsPendingTrailingCallAndRunsImmediately() {
        let throttler = Throttler(interval: 5)
        var values: [Int] = []

        throttler.call { values.append(1) } // immediate
        throttler.call { values.append(2) } // scheduled trailing, 5s out — must never fire
        throttler.flushNow { values.append(3) } // cancels the pending trailing call, runs now

        XCTAssertEqual(values, [1, 3]) // "2" must never appear — this is the eraseEverything() guarantee
    }

    /// The exact scenario AppState.eraseEverything() depends on: a pending
    /// throttled write must not land after a flushNow, even if we wait past
    /// the original interval.
    func test_flushNow_preventsStaleTrailingWriteFromLandingLater() {
        let throttler = Throttler(interval: 0.15)
        var values: [Int] = []

        throttler.call { values.append(1) }   // immediate
        throttler.call { values.append(999) } // would-be stale trailing write
        throttler.flushNow { values.append(2) } // erase-equivalent: cancel + run now

        let expectation = expectation(description: "wait past the original interval")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(values, [1, 2]) // 999 never lands, even after waiting past the interval
    }
}
