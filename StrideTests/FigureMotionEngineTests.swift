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

    // MARK: - Rig V2 continuity

    /// No state change may cause a visible discontinuity in the gait
    /// parameters — the state machine only ever moves targets, and the
    /// easing does the rest.
    func test_gaitParametersAreContinuousAcrossStateChanges() {
        var engine = FigureMotionEngine(now: .init())
        var t = Date()
        var previous = engine.update(idle(), now: t)
        var sawStateChange = false
        var lastState = engine.state

        for i in 1...400 {
            t = t.addingTimeInterval(1.0 / 30)
            let input: FigureMotionInputs
            switch i {
            case ..<60:   input = idle()
            case ..<160:  input = moving(cadence: 110, intensity: 0.45)
            case ..<240:  input = moving(cadence: 170, intensity: 0.95)
            default:      input = idle()
            }
            let g = engine.update(input, now: t)
            if engine.state != lastState { sawStateChange = true; lastState = engine.state }

            XCTAssertLessThan(abs(g.strideLength - previous.strideLength), 3.0)
            XCTAssertLessThan(abs(g.runBlend - previous.runBlend), 0.2)
            XCTAssertLessThan(abs(g.forwardLean - previous.forwardLean), 2.0)
            XCTAssertLessThan(abs(g.weightShift - previous.weightShift), 1.0)
            previous = g
        }
        XCTAssertTrue(sawStateChange, "test never exercised a transition")
    }

    func test_sustainedRunningInputReachesRunningMechanics() {
        var engine = FigureMotionEngine(now: .init())
        var t = Date()
        var g = engine.update(idle(), now: t)
        for _ in 0..<200 {
            t = t.addingTimeInterval(1.0 / 30)
            g = engine.update(moving(cadence: 175, intensity: 1.0), now: t)
        }
        XCTAssertEqual(engine.state, .locomotion)
        XCTAssertGreaterThan(g.runBlend, 0.8)
        XCTAssertLessThan(FigureGait.dutyFactor(runBlend: g.runBlend), 0.5,
                          "sustained running input should open a flight phase")
    }

    func test_sustainedWalkingInputStaysInWalkingMechanics() {
        var engine = FigureMotionEngine(now: .init())
        var t = Date()
        var g = engine.update(idle(), now: t)
        for _ in 0..<200 {
            t = t.addingTimeInterval(1.0 / 30)
            g = engine.update(moving(cadence: 108, intensity: 0.45), now: t)
        }
        XCTAssertLessThan(g.runBlend, 0.05)
        XCTAssertGreaterThan(FigureGait.dutyFactor(runBlend: g.runBlend), 0.5,
                             "walking must always keep a foot on the ground")
    }

    /// SLOWING should shed turnover faster than it sheds stride, so the
    /// last steps read long and heavy instead of the gait simply fading.
    func test_slowingLosesCadenceFasterThanStride() {
        let t0 = Date()
        var engine = engineInLocomotion(at: t0)
        var t = t0.addingTimeInterval(MotionConfig.risingDuration + 0.1)
        for _ in 0..<10 {
            t = t.addingTimeInterval(1.0 / 30)
            _ = engine.update(moving(cadence: 130, intensity: 0.7), now: t)
        }
        let before = engine.gait
        _ = engine.update(idle(), now: t.addingTimeInterval(0.05))
        XCTAssertEqual(engine.state, .slowing)

        for _ in 0..<12 {
            t = t.addingTimeInterval(1.0 / 30)
            _ = engine.update(idle(), now: t)
        }
        let after = engine.gait
        let cadenceRetained = before.cadence > 0 ? after.cadence / before.cadence : 0
        let strideRetained = before.strideLength > 0 ? Double(after.strideLength / before.strideLength) : 0
        XCTAssertLessThan(cadenceRetained, strideRetained,
                          "cadence should decay faster than stride during SLOWING")
    }

    func test_risingShiftsWeightRatherThanStepping() {
        var engine = FigureMotionEngine(now: .init())
        var t = Date()
        _ = engine.update(moving(), now: t)
        XCTAssertEqual(engine.state, .rising)
        for _ in 0..<5 {
            t = t.addingTimeInterval(1.0 / 60)
            _ = engine.update(moving(), now: t)
        }
        XCTAssertGreaterThan(engine.gait.weightShift, 0, "RISING should transfer weight")
        XCTAssertLessThan(engine.gait.strideLength, 2.0, "RISING should not take a step yet")
    }

    func test_restlessDoesNotWalk() {
        var engine = FigureMotionEngine(now: .init())
        var t = Date()
        _ = engine.update(idle(), now: t)
        for _ in 0..<20 {
            t = t.addingTimeInterval(1.0 / 30)
            _ = engine.update(idle(inactiveDuration: MotionConfig.restlessInactivityThreshold + 30), now: t)
        }
        XCTAssertEqual(engine.state, .restless)
        XCTAssertLessThan(engine.gait.strideLength, 0.5, "RESTLESS must never take a step")
        XCTAssertGreaterThan(engine.gait.weightShift, 0)
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
