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

    /// A session that ended after a sustained pause must not leave anything
    /// behind that prevents a clean new session from starting — no stuck
    /// state, no stale "already in a session" flag.
    ///
    /// Note on timing: a single fresh sample right after a long gap has no
    /// prior point left in the window to diff against (the old samples
    /// were trimmed once they aged past sampleWindow), so stepsInWindow
    /// reads 0 for that first sample alone — this is inherent to a
    /// windowed-delta design, not new here, and matches the already-shipped
    /// classifier's real-device behavior (confirmed working via TestFlight
    /// last phase): resuming from a pause takes one more sample before it
    /// registers, same as it would after any cold start.
    func test_movementResumesCleanly_afterSessionEnds() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        c.record(steps: 5, at: t0.addingTimeInterval(1))
        _ = c.evaluate(now: t0.addingTimeInterval(1)) // session 1 starts

        let endTime = t0.addingTimeInterval(1 + MotionConfig.sessionEndInactivity + 1)
        let ended = c.evaluate(now: endTime)
        XCTAssertFalse(ended.isInMovementSession) // session 1 has ended

        // First sample back has nothing to diff against yet.
        c.record(steps: 5, at: endTime.addingTimeInterval(1))
        let firstSampleBack = c.evaluate(now: endTime.addingTimeInterval(1))
        XCTAssertFalse(firstSampleBack.isInMovementSession)
        XCTAssertEqual(firstSampleBack.activityState, .idle)

        // The next real sample gives the window its first real delta —
        // this is where a resumed session actually becomes visible.
        c.record(steps: 10, at: endTime.addingTimeInterval(2))
        let resumed = c.evaluate(now: endTime.addingTimeInterval(2))

        XCTAssertTrue(resumed.isInMovementSession)
        XCTAssertEqual(resumed.movementSessionStartedAt, endTime.addingTimeInterval(2))
        XCTAssertEqual(resumed.activityState, .walking)
    }

    // MARK: - Cadence (Phase 1.1A)

    func test_cadence_stationary_staysZero() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        let snap = c.evaluate(now: t0)
        XCTAssertEqual(snap.smoothedCadence, 0)
    }

    func test_cadence_slowMovement_producesModestReading() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        // 1 step/sec ~= 60 steps/min.
        for i in 1...8 {
            c.record(steps: i, at: t0.addingTimeInterval(Double(i)))
            _ = c.evaluate(now: t0.addingTimeInterval(Double(i)))
        }
        let snap = c.evaluate(now: t0.addingTimeInterval(8))
        XCTAssertGreaterThan(snap.smoothedCadence, 20)
        XCTAssertLessThan(snap.smoothedCadence, 90)
    }

    func test_cadence_fasterMovement_readsHigherThanSlow() {
        var slow = MovementClassifier()
        var fast = MovementClassifier()
        let t0 = Date()
        slow.record(steps: 0, at: t0)
        fast.record(steps: 0, at: t0)
        for i in 1...8 {
            let t = t0.addingTimeInterval(Double(i))
            slow.record(steps: i, at: t) // ~1 step/sec
            fast.record(steps: i * 3, at: t) // ~3 steps/sec
            _ = slow.evaluate(now: t)
            _ = fast.evaluate(now: t)
        }
        let slowSnap = slow.evaluate(now: t0.addingTimeInterval(8))
        let fastSnap = fast.evaluate(now: t0.addingTimeInterval(8))
        XCTAssertGreaterThan(fastSnap.smoothedCadence, slowSnap.smoothedCadence)
    }

    func test_cadence_accelerating_trendsUpward() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        var cumulative = 0
        var readings: [Double] = []
        // Ramp from 1 step/sec to 4 steps/sec.
        for second in 1...6 {
            cumulative += second
            let t = t0.addingTimeInterval(Double(second))
            c.record(steps: cumulative, at: t)
            readings.append(c.evaluate(now: t).smoothedCadence)
        }
        XCTAssertGreaterThan(readings.last!, readings.first!)
    }

    func test_cadence_decelerating_trendsDownward() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        var cumulative = 0
        // Establish a brisk cadence first.
        for second in 1...5 {
            cumulative += 3
            let t = t0.addingTimeInterval(Double(second))
            c.record(steps: cumulative, at: t)
            _ = c.evaluate(now: t)
        }
        let peak = c.evaluate(now: t0.addingTimeInterval(5)).smoothedCadence

        // Then slow to a crawl.
        for second in 6...10 {
            cumulative += 1
            let t = t0.addingTimeInterval(Double(second))
            c.record(steps: cumulative, at: t)
            _ = c.evaluate(now: t)
        }
        let after = c.evaluate(now: t0.addingTimeInterval(10)).smoothedCadence
        XCTAssertLessThan(after, peak)
    }

    func test_cadence_decaysTowardZero_whenSamplesGoStale() {
        var c = MovementClassifier()
        let t0 = Date()
        c.record(steps: 0, at: t0)
        for i in 1...5 {
            c.record(steps: i * 2, at: t0.addingTimeInterval(Double(i)))
            _ = c.evaluate(now: t0.addingTimeInterval(Double(i)))
        }
        let peak = c.evaluate(now: t0.addingTimeInterval(5)).smoothedCadence
        XCTAssertGreaterThan(peak, 0)

        // Long gap, no new samples — should decay well below its peak,
        // not stay frozen at the last real value.
        let stale = c.evaluate(now: t0.addingTimeInterval(15)).smoothedCadence
        XCTAssertLessThan(stale, peak)
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
