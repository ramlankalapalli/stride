import XCTest
@testable import Stride

final class MovementClassifierTests: XCTestCase {

    func test_noSamples_isIdle() {
        var c = MovementClassifier()
        let snap = c.evaluate()
        XCTAssertEqual(snap.activityState, .idle)
        XCTAssertEqual(snap.motionIntensity, 0)
    }

    func test_moderateStepsInWindow_isWalking() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        c.record(steps: 6, at: t0.addingTimeInterval(2)) // over walking(4), under active(20)
        let snap = c.evaluate(now: t0.addingTimeInterval(2))
        XCTAssertEqual(snap.activityState, .walking)
    }

    func test_highStepsInWindow_isActive() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        c.record(steps: 25, at: t0.addingTimeInterval(2))
        let snap = c.evaluate(now: t0.addingTimeInterval(2))
        XCTAssertEqual(snap.activityState, .active)
    }

    func test_fewIncidentalSteps_remainIdle() {
        // The original cadence bug this guards against: 1-2 incidental
        // steps from picking up the phone must not read as "walking".
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        c.record(steps: 2, at: t0.addingTimeInterval(1))
        let snap = c.evaluate(now: t0.addingTimeInterval(1))
        XCTAssertEqual(snap.activityState, .idle)
    }

    func test_staleSamples_areTreatedAsIdle() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        c.record(steps: 10, at: t0.addingTimeInterval(1))
        // Well past sampleStaleness (6s) — even though within sampleWindow.
        let snap = c.evaluate(now: t0.addingTimeInterval(8))
        XCTAssertEqual(snap.activityState, .idle)
    }

    func test_risingIntensity_isDetected() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        _ = c.evaluate(now: t0) // establishes a near-zero baseline
        c.record(steps: 25, at: t0.addingTimeInterval(1))
        let snap = c.evaluate(now: t0.addingTimeInterval(1))
        XCTAssertEqual(snap.trend, .rising)
    }

    func test_fallingIntensity_isDetected() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        c.record(steps: 25, at: t0.addingTimeInterval(1))
        _ = c.evaluate(now: t0.addingTimeInterval(1)) // high baseline

        // Far enough forward that the burst has aged out of the window.
        let snap = c.evaluate(now: t0.addingTimeInterval(13))
        XCTAssertEqual(snap.trend, .falling)
    }

    func test_sessionStarts_onRealStepThreshold() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        c.record(steps: 5, at: t0.addingTimeInterval(1))
        let snap = c.evaluate(now: t0.addingTimeInterval(1))
        XCTAssertTrue(snap.isInMovementSession)
        XCTAssertNotNil(snap.movementSessionStartedAt)
        XCTAssertNotNil(snap.lastMeaningfulMovementAt)
    }

    func test_shortPause_doesNotEndSession() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        c.record(steps: 5, at: t0.addingTimeInterval(1))
        _ = c.evaluate(now: t0.addingTimeInterval(1)) // session starts

        // 20s pause — the pose-level state already goes idle (well past the
        // 6s staleness window), but a movement session tolerates far more
        // than that; sessionEndInactivity is 90s.
        let snap = c.evaluate(now: t0.addingTimeInterval(21))
        XCTAssertEqual(snap.activityState, .idle)
        XCTAssertTrue(snap.isInMovementSession)
    }

    func test_sustainedPause_endsSession() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        c.record(steps: 5, at: t0.addingTimeInterval(1))
        _ = c.evaluate(now: t0.addingTimeInterval(1))

        let snap = c.evaluate(now: t0.addingTimeInterval(1 + MotionConfig.sessionEndInactivity + 1))
        XCTAssertFalse(snap.isInMovementSession)
        XCTAssertNil(snap.movementSessionStartedAt)
    }

    func test_reset_clearsAllState() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        c.record(steps: 25, at: t0.addingTimeInterval(1))
        _ = c.evaluate(now: t0.addingTimeInterval(1))

        c.reset()
        let snap = c.evaluate(now: t0.addingTimeInterval(1))
        XCTAssertEqual(snap.activityState, .idle)
        XCTAssertEqual(snap.motionIntensity, 0)
        XCTAssertFalse(snap.isInMovementSession)
        XCTAssertNil(snap.lastMeaningfulMovementAt)
        XCTAssertNil(snap.inactiveDuration)
    }
}
