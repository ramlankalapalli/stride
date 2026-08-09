import XCTest
@testable import Stride

final class FigureMotionEngineTests: XCTestCase {

    private func moving(cadence: Double = 100, intensity: Double = 0.6, trend: MovementTrend = .steady) -> FigureMotionInputs {
        FigureMotionInputs(activityState: .walking, motionIntensity: intensity, movementTrend: trend,
                           isInMovementSession: true, movementSessionDuration: 1, inactiveDuration: 0,
                           smoothedCadence: cadence)
    }

    private func idle(inactiveDuration: TimeInterval? = nil) -> FigureMotionInputs {
        FigureMotionInputs(activityState: .idle, motionIntensity: 0, movementTrend: .steady,
                           isInMovementSession: false, movementSessionDuration: nil,
                           inactiveDuration: inactiveDuration, smoothedCadence: 0)
    }

    func test_initialState_isStill() {
        let engine = FigureMotionEngine()
        XCTAssertEqual(engine.state, .still)
    }

    func test_movementBegins_entersRising() {
        var engine = FigureMotionEngine(now: .init())
        let t0 = Date()
        _ = engine.update(idle(), now: t0)
        _ = engine.update(moving(), now: t0.addingTimeInterval(0.05))
        XCTAssertEqual(engine.state, .rising)
    }

    func test_risingSettles_intoLocomotion() {
        var engine = FigureMotionEngine(now: .init())
        let t0 = Date()
        _ = engine.update(moving(), now: t0)
        XCTAssertEqual(engine.state, .rising)
        _ = engine.update(moving(), now: t0.addingTimeInterval(MotionConfig.risingDuration + 0.05))
        XCTAssertEqual(engine.state, .locomotion)
    }

    private func engineInLocomotion(at t0: Date) -> FigureMotionEngine {
        var engine = FigureMotionEngine(now: t0)
        _ = engine.update(moving(), now: t0)
        _ = engine.update(moving(), now: t0.addingTimeInterval(MotionConfig.risingDuration + 0.05))
        return engine
    }

    func test_locomotion_toSlowing_onIdleOrFallingTrend() {
        let t0 = Date()
        var engine = engineInLocomotion(at: t0)
        let t1 = t0.addingTimeInterval(MotionConfig.risingDuration + 0.1)
        _ = engine.update(idle(), now: t1.addingTimeInterval(0.1))
        XCTAssertEqual(engine.state, .slowing)
    }

    func test_slowing_toRecovering_afterReleaseWindow() {
        let t0 = Date()
        var engine = engineInLocomotion(at: t0)
        var t = t0.addingTimeInterval(MotionConfig.risingDuration + 0.1)
        _ = engine.update(idle(), now: t)
        XCTAssertEqual(engine.state, .slowing)

        t = t.addingTimeInterval(MotionConfig.slowingReleaseDuration + 0.1)
        _ = engine.update(idle(), now: t)
        XCTAssertEqual(engine.state, .recovering)
    }

    func test_recovering_toStill_afterRecoveryDuration() {
        let t0 = Date()
        var engine = engineInLocomotion(at: t0)
        var t = t0.addingTimeInterval(MotionConfig.risingDuration + 0.1)
        _ = engine.update(idle(), now: t) // -> slowing
        t = t.addingTimeInterval(MotionConfig.slowingReleaseDuration + 0.1)
        _ = engine.update(idle(), now: t) // -> recovering
        XCTAssertEqual(engine.state, .recovering)

        t = t.addingTimeInterval(MotionConfig.recoveryDuration + 0.1)
        _ = engine.update(idle(), now: t)
        XCTAssertEqual(engine.state, .still)
    }

    func test_longInactivity_entersRestless() {
        var engine = FigureMotionEngine(now: .init())
        let t0 = Date()
        _ = engine.update(idle(), now: t0)
        _ = engine.update(idle(inactiveDuration: MotionConfig.restlessInactivityThreshold + 1), now: t0.addingTimeInterval(1))
        XCTAssertEqual(engine.state, .restless)
    }

    func test_veryLongInactivity_entersResting() {
        var engine = FigureMotionEngine(now: .init())
        let t0 = Date()
        _ = engine.update(idle(), now: t0)
        _ = engine.update(idle(inactiveDuration: MotionConfig.restingInactivityThreshold + 1), now: t0.addingTimeInterval(1))
        XCTAssertEqual(engine.state, .resting)
    }

    /// Hysteresis: a single noisy tick that flickers "moving" then "idle"
    /// while already easing out of locomotion must not immediately snap
    /// back and forth — SLOWING has to have run for at least
    /// minSlowingDwellBeforeResume before a moving signal is honored again.
    func test_slowing_doesNotFlapOnImmediateMovingBlip() {
        let t0 = Date()
        var engine = engineInLocomotion(at: t0)
        var t = t0.addingTimeInterval(MotionConfig.risingDuration + 0.1)
        _ = engine.update(idle(), now: t)
        XCTAssertEqual(engine.state, .slowing)

        // A moving reading arrives almost immediately — before the
        // hysteresis dwell has elapsed. Must still read as slowing.
        t = t.addingTimeInterval(0.05)
        _ = engine.update(moving(), now: t)
        XCTAssertEqual(engine.state, .slowing)
    }

    func test_slowing_resumesLocomotion_afterHysteresisDwell() {
        let t0 = Date()
        var engine = engineInLocomotion(at: t0)
        var t = t0.addingTimeInterval(MotionConfig.risingDuration + 0.1)
        _ = engine.update(idle(), now: t)
        XCTAssertEqual(engine.state, .slowing)

        t = t.addingTimeInterval(MotionConfig.minSlowingDwellBeforeResume + 0.05)
        _ = engine.update(moving(), now: t)
        XCTAssertEqual(engine.state, .locomotion)
    }

    func test_gaitParameters_stayFiniteAcrossASession() {
        var engine = FigureMotionEngine(now: .init())
        var t = Date()
        var g = engine.update(idle(), now: t)
        for i in 1...50 {
            t = t.addingTimeInterval(0.1)
            let input = i < 25 ? moving(cadence: 90 + Double(i)) : idle()
            g = engine.update(input, now: t)
            XCTAssertTrue(g.phase.isFinite)
            XCTAssertTrue(g.strideLength.isFinite)
            XCTAssertTrue(g.forwardLean.isFinite)
        }
    }
}
