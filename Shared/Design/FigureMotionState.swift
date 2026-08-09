import Foundation
import CoreGraphics

// Phase 1.1A — Figure Motion Engine, part 2: the postural state machine.
//
// This is deliberately small. CASUAL/WALKING/BRISK/RUNNING are NOT states
// here — they're all read off the single `.locomotion` state's continuous
// gait parameters (see FigureRig), which move smoothly with intensity/
// cadence. The states below exist only for the postural transitions that
// really are discrete: whether the figure is moving at all, and how it
// enters/leaves motion.
//
// Lives in Shared/Design (not Stride/Logic) because AvatarView — shared with
// the widget target — hosts the engine that drives LiveAvatar.

/// Rising/steady/falling read on recent movement intensity.
///
/// Moved here from MovementClassifier (Stride/Logic, app-target-only) for
/// the same reason ActivityState lives in this file's neighbor
/// (AvatarView.swift): the widget target compiles this whole folder, so any
/// type referenced from here needs to live where both targets can see it.
enum MovementTrend {
    case rising, steady, falling
}

/// The Figure's current postural/transition state. Never drawn directly —
/// each state just points the continuous gait parameters toward a target;
/// FigureMotionEngine eases the actual numbers there.
enum FigureMotionState: Equatable {
    /// Neutral standing, extremely subtle life (breathing/weight shift).
    case still
    /// Brief anticipation as a movement session begins — weight shifts
    /// forward before the first real gait cycle.
    case rising
    /// The one continuous locomotion system. CASUAL/WALKING/BRISK/RUNNING
    /// are all readings of this state's gait parameters at different
    /// intensity/cadence, not separate states.
    case locomotion
    /// Real physical deceleration — gait parameters ease down instead of
    /// snapping to idle.
    case slowing
    /// Restrained post-session settle: posture returns upright, small
    /// residual motion, no dramatic exhaustion animation.
    case recovering
    /// After meaningful inactivity — a restrained, non-nagging weight
    /// shift/posture change. Never sad, guilty or impatient.
    case restless
    /// Calm long-idle posture. The product never shames the user for it.
    case resting
}

/// Everything the engine needs to decide what the Figure should be doing
/// right now. Mirrors the signals already published by StepProvider —
/// deliberately no new signal is required beyond smoothedCadence (added to
/// MovementClassifier alongside this phase).
struct FigureMotionInputs {
    var activityState: ActivityState
    var motionIntensity: Double
    var movementTrend: MovementTrend
    var isInMovementSession: Bool
    var movementSessionDuration: TimeInterval?
    var inactiveDuration: TimeInterval?
    var smoothedCadence: Double

    static let idle = FigureMotionInputs(
        activityState: .idle, motionIntensity: 0, movementTrend: .steady,
        isInMovementSession: false, movementSessionDuration: nil,
        inactiveDuration: nil, smoothedCadence: 0
    )
}

/// Pure, headless state machine + gait-parameter smoother. No CoreMotion, no
/// SwiftUI — call `update(_:now:)` on a cadence (a display-linked timer, a
/// TimelineView tick, or a unit test loop) and it hands back the gait
/// parameters to render this instant.
///
/// Two things happen inside `update`, every call:
///  1. Decide whether the postural state should change (with hysteresis —
///     see `nextState`), based on dwell time and the incoming signals.
///  2. Exponentially ease the current gait parameters toward whatever the
///     (possibly new) state's target parameters are, using elapsed wall
///     time so the result is identical regardless of call frequency.
struct FigureMotionEngine {
    private(set) var state: FigureMotionState = .still
    private(set) var gait: FigureGaitParameters = .neutral

    private var stateEnteredAt: Date
    private var lastUpdateAt: Date?
    private var lastRestlessEndedAt: Date?

    init(now: Date = Date()) {
        stateEnteredAt = now
    }

    @discardableResult
    mutating func update(_ inputs: FigureMotionInputs, now: Date = Date()) -> FigureGaitParameters {
        let dt = lastUpdateAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        lastUpdateAt = now

        let dwellBeforeTick = now.timeIntervalSince(stateEnteredAt)
        let resolved = nextState(from: state, dwell: dwellBeforeTick, inputs: inputs, now: now)
        if resolved != state {
            if state == .restless { lastRestlessEndedAt = now }
            state = resolved
            stateEnteredAt = now
        }
        let dwellInState = now.timeIntervalSince(stateEnteredAt)

        let target = targetGait(for: state, inputs: inputs, previousPhase: gait.phase, dwellInState: dwellInState)

        let alpha = dt > 0 ? 1 - exp(-MotionConfig.gaitSmoothingRate * dt) : 0
        gait.intensity = lerp(gait.intensity, target.intensity, alpha)
        gait.strideLength = lerp(gait.strideLength, target.strideLength, alpha)
        gait.forwardLean = lerp(gait.forwardLean, target.forwardLean, alpha)
        gait.armSwing = lerp(gait.armSwing, target.armSwing, alpha)
        gait.verticalBob = lerp(gait.verticalBob, target.verticalBob, alpha)
        gait.energy = lerp(gait.energy, target.energy, alpha)
        gait.cadence = lerp(gait.cadence, target.cadence, alpha)
        // runBlend rides the same easing as everything else, so the duty
        // factor crosses 0.5 — and the flight phase opens — gradually.
        // Nothing anywhere switches on it.
        gait.runBlend = lerp(gait.runBlend, target.runBlend, alpha)
        gait.weightShift = lerp(gait.weightShift, target.weightShift, alpha)

        let hz = cycleRate(for: state, cadence: gait.cadence)
        var phase = gait.phase + hz * dt
        phase = phase.truncatingRemainder(dividingBy: 1)
        if phase < 0 { phase += 1 }
        gait.phase = phase

        return gait
    }

    // MARK: - Transitions

    private func nextState(from current: FigureMotionState, dwell: TimeInterval, inputs: FigureMotionInputs, now: Date) -> FigureMotionState {
        let moving = inputs.isInMovementSession || inputs.activityState != .idle

        switch current {
        case .still:
            if moving { return .rising }
            if let inactive = inputs.inactiveDuration {
                if inactive > MotionConfig.restingInactivityThreshold { return .resting }
                if inactive > MotionConfig.restlessInactivityThreshold, canEnterRestless(now: now) { return .restless }
            }
            return .still

        case .rising:
            if !moving { return .still }
            if dwell >= MotionConfig.risingDuration { return .locomotion }
            return .rising

        case .locomotion:
            if inputs.activityState == .idle || inputs.movementTrend == .falling { return .slowing }
            return .locomotion

        case .slowing:
            // Hysteresis: a single noisy tick back into "moving" isn't
            // enough to snap straight back to locomotion — the release has
            // to have been running a little while first, or a moving/idle
            // flicker every tick would make the figure stutter.
            if moving, inputs.movementTrend != .falling, dwell >= MotionConfig.minSlowingDwellBeforeResume {
                return .locomotion
            }
            if dwell >= MotionConfig.slowingReleaseDuration { return .recovering }
            return .slowing

        case .recovering:
            if moving { return .rising }
            if dwell >= MotionConfig.recoveryDuration { return .still }
            return .recovering

        case .restless:
            if moving { return .rising }
            if let inactive = inputs.inactiveDuration, inactive > MotionConfig.restingInactivityThreshold { return .resting }
            if dwell >= MotionConfig.restlessCycleDuration { return .still }
            return .restless

        case .resting:
            if moving { return .rising }
            return .resting
        }
    }

    private func canEnterRestless(now: Date) -> Bool {
        guard let last = lastRestlessEndedAt else { return true }
        return now.timeIntervalSince(last) >= MotionConfig.restlessCooldown
    }

    // MARK: - Target gait per state

    private func targetGait(for state: FigureMotionState, inputs: FigureMotionInputs, previousPhase: Double, dwellInState: TimeInterval) -> FigureGaitParameters {
        let intensity = min(1, max(0, inputs.motionIntensity))

        switch state {
        case .still:
            return FigureGaitParameters(phase: previousPhase, intensity: 0, strideLength: 0, cadence: 0,
                                        forwardLean: 0, armSwing: 0, verticalBob: MotionConfig.stillBreathingBob,
                                        energy: 0, runBlend: 0, weightShift: 0)

        case .resting:
            return FigureGaitParameters(phase: previousPhase, intensity: 0, strideLength: 0, cadence: 0,
                                        forwardLean: 0, armSwing: 0, verticalBob: MotionConfig.restingBob,
                                        energy: 0, runBlend: 0, weightShift: 0)

        case .restless:
            // A shift of weight, not a step: the pelvis moves laterally and
            // the feet stay exactly where they are. V1 borrowed strideLength
            // for this, which under V2's mechanics would literally make the
            // Figure walk.
            return FigureGaitParameters(phase: previousPhase, intensity: 0, strideLength: 0, cadence: 0,
                                        forwardLean: 0, armSwing: 0, verticalBob: MotionConfig.stillBreathingBob,
                                        energy: 0.15, runBlend: 0,
                                        weightShift: MotionConfig.restlessWeightShift)

        case .rising:
            // Intent, communicated by taking weight onto one side and
            // letting the pelvis settle very slightly — negative bob eases
            // downward. Not a crouch, and no step is taken yet.
            return FigureGaitParameters(phase: previousPhase, intensity: 0.25, strideLength: 0, cadence: 0,
                                        forwardLean: MotionConfig.risingLeanDegrees, armSwing: 0,
                                        verticalBob: -MotionConfig.risingPelvisSettle, energy: 0.25,
                                        runBlend: 0, weightShift: MotionConfig.risingWeightShift)

        case .locomotion:
            let blend = FigureGait.runBlend(cadence: inputs.smoothedCadence, intensity: intensity)
            return FigureGaitParameters(
                phase: previousPhase,
                intensity: intensity,
                strideLength: mix(MotionConfig.strideLengthMin, MotionConfig.strideLengthMax, intensity),
                cadence: inputs.smoothedCadence,
                forwardLean: mixD(MotionConfig.forwardLeanMin, MotionConfig.forwardLeanMax, intensity),
                armSwing: mix(MotionConfig.armSwingMin, MotionConfig.armSwingMax, intensity),
                verticalBob: mix(MotionConfig.locomotionBobMin, MotionConfig.locomotionBobMax, intensity),
                energy: max(0.35, intensity),
                runBlend: blend,
                weightShift: 0
            )

        case .slowing:
            // Real deceleration has a shape: turnover drops away first and
            // the stride keeps most of its length for a moment, so the last
            // few steps read as long and heavy rather than as the whole
            // gait fading out uniformly. Running mechanics let go fastest.
            let decay = max(0, 1 - dwellInState / MotionConfig.slowingReleaseDuration)
            let cadenceDecay = pow(decay, 1.6)
            let strideDecay = pow(decay, 0.7)
            return FigureGaitParameters(
                phase: previousPhase,
                intensity: intensity * decay,
                strideLength: mix(MotionConfig.strideLengthMin, MotionConfig.strideLengthMax, intensity) * CGFloat(strideDecay),
                cadence: inputs.smoothedCadence * cadenceDecay,
                forwardLean: mixD(MotionConfig.forwardLeanMin, MotionConfig.forwardLeanMax, intensity) * decay,
                armSwing: mix(MotionConfig.armSwingMin, MotionConfig.armSwingMax, intensity) * CGFloat(strideDecay),
                verticalBob: mix(MotionConfig.locomotionBobMin, MotionConfig.locomotionBobMax, intensity) * CGFloat(decay),
                energy: max(0.15, intensity) * decay,
                runBlend: FigureGait.runBlend(cadence: inputs.smoothedCadence, intensity: intensity) * pow(decay, 2),
                weightShift: 0
            )

        case .recovering:
            // Momentum settling out, not exhaustion: a small residual sway
            // decaying to nothing, feet already planted.
            let residual = max(0, 1 - dwellInState / MotionConfig.recoveryDuration)
            return FigureGaitParameters(phase: previousPhase, intensity: 0, strideLength: 0, cadence: 0,
                                        forwardLean: 0, armSwing: 0,
                                        verticalBob: MotionConfig.recoveringResidualBob * CGFloat(residual),
                                        energy: 0, runBlend: 0,
                                        weightShift: MotionConfig.restlessWeightShift * CGFloat(residual) * 0.5)
        }
    }

    private func cycleRate(for state: FigureMotionState, cadence: Double) -> Double {
        switch state {
        case .still: return MotionConfig.breathingCycleHz
        case .resting: return MotionConfig.restingCycleHz
        case .restless: return MotionConfig.restlessCycleHz
        case .rising: return MotionConfig.risingCycleHz
        case .recovering: return MotionConfig.recoveringCycleHz
        case .locomotion, .slowing:
            // Two steps per full left/right gait cycle.
            return max(MotionConfig.locomotionMinCycleHz, cadence / 60 / 2)
        }
    }
}

#if DEBUG || STRIDE_INTERNAL_TESTING
extension FigureMotionEngine {
    /// Figure Lab only: jump straight to a postural state for preview,
    /// bypassing the normal transition rules. Never compiled into a normal
    /// release build — see FigureLabScreen.swift. Whatever inputs the
    /// caller keeps feeding `update` afterward still govern where the
    /// engine goes next — this only sets the starting point.
    mutating func debugForceState(_ state: FigureMotionState, now: Date = Date()) {
        self.state = state
        self.stateEnteredAt = now
    }
}
#endif

private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
private func mix(_ lo: CGFloat, _ hi: CGFloat, _ t: Double) -> CGFloat { lo + CGFloat(t) * (hi - lo) }
private func mixD(_ lo: Double, _ hi: Double, _ t: Double) -> Double { lo + t * (hi - lo) }
