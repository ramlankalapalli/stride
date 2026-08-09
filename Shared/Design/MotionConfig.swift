import SwiftUI

// Foundation-hardening pass — Phase 1.0.5.
//
// Every tunable number for movement classification and Figure motion, in one
// place. Previously scattered as inline literals across StepProvider.swift
// and AvatarView.swift — product/design tuning now touches one file instead
// of hunting through two unrelated ones. Lives in Shared/Design (not
// Stride/Logic) because AvatarView (shared with the widget target) needs the
// animation half of this just as much as StepProvider needs the
// classification half.

enum MotionConfig {

    // MARK: - Classification (StepProvider / MovementClassifier)

    /// Rolling sample buffer length — how far back "right now" looks.
    static let sampleWindow: TimeInterval = 12
    /// No sample newer than this within the window → treated as idle/stale.
    static let sampleStaleness: TimeInterval = 6
    /// How often the classifier re-evaluates (Timer cadence in StepProvider).
    static let classifierTickInterval: TimeInterval = 3

    /// Steps within `sampleWindow` needed to call it "walking".
    static let walkingStepThreshold = 4
    /// Steps within `sampleWindow` needed to call it "active" (~100+ steps/min).
    static let activeStepThreshold = 20

    /// Continuous intensity (0...1) formula: (stepsInWindow - floor) / range.
    static let intensityFloorSteps: Double = 2
    static let intensityRangeSteps: Double = 28
    /// Minimum intensity delta between ticks to call it rising/falling
    /// rather than steady — filters single-step noise from flapping the trend.
    static let trendHysteresis: Double = 0.08

    // MARK: - Session / inactivity hysteresis

    /// Steps within `sampleWindow` needed to (re)start a movement session.
    static let sessionStartStepThreshold = 4
    /// A session survives short pauses; only a pause this long ends it.
    static let sessionEndInactivity: TimeInterval = 90

    // MARK: - Hourly waveform

    /// How often the *current hour only* is re-queried and refreshed.
    static let hourlyRefreshInterval: TimeInterval = 60

    // MARK: - Persistence

    /// High-frequency step deltas are coalesced to at most one disk write
    /// per this interval. Reward/manual/lifecycle events bypass this.
    static let persistenceDebounceInterval: TimeInterval = 5

    // MARK: - Figure animation (LiveAvatar)

    static let bobAmplitudeMin: CGFloat = 2.5
    static let bobAmplitudeMax: CGFloat = 8.0
    static let bobDurationMin: Double = 0.34
    static let bobDurationMax: Double = 0.62
    static let leanMaxDegrees: Double = 5
    static let runningScaleMax: CGFloat = 1.05

    static let poseTransitionSpringResponse: Double = 0.5
    static let poseTransitionSpringDamping: Double = 0.7
    static let walkingSpringResponse: Double = 0.5
    static let walkingSpringDamping: Double = 0.8
    static let runningSpringResponse: Double = 0.4
    static let runningSpringDamping: Double = 0.75

    static let breakthroughInResponse: Double = 0.22
    static let breakthroughInDamping: Double = 0.45
    static let breakthroughOutResponse: Double = 0.32
    static let breakthroughOutDamping: Double = 0.8
    static let breakthroughHoldDuration: Double = 0.18
    static let breakthroughScale: CGFloat = 1.1
    static let breakthroughOffsetX: CGFloat = 5

    /// Reduce Motion replacement for the spring/repeatForever/pulse set
    /// above — one restrained crossfade duration used everywhere motion
    /// would otherwise be exaggerated.
    static let reducedMotionCrossfadeDuration: Double = 0.2

    // MARK: - Cadence smoothing (MovementClassifier, Phase 1.1A)

    /// Per-second exponential convergence rate for smoothedCadence easing
    /// toward the instantaneous reading (or toward 0 when samples go
    /// stale). Higher = snappier, lower = smoother/noisier-resistant.
    static let cadenceSmoothingRate: Double = 0.6
    /// Below this inter-sample gap, an instantaneous rate reading is
    /// treated as too noisy to trust and the previous smoothed value is
    /// reused instead.
    static let cadenceMinSampleGap: TimeInterval = 0.15

    // MARK: - Figure Motion Engine (Phase 1.1A) — postural timing

    /// Brief anticipation before the first real gait cycle.
    static let risingDuration: TimeInterval = 0.32
    /// How long a real deceleration takes before settling into recovery.
    static let slowingReleaseDuration: TimeInterval = 1.1
    /// How long the restrained post-session settle lasts before STILL.
    static let recoveryDuration: TimeInterval = 1.6
    /// Minimum time SLOWING must have been running before a moving signal
    /// is allowed to snap it back to LOCOMOTION — hysteresis against a
    /// single noisy idle tick causing visible stutter.
    static let minSlowingDwellBeforeResume: TimeInterval = 0.4
    /// Meaningful inactivity before a restrained restless weight shift.
    static let restlessInactivityThreshold: TimeInterval = 20 * 60
    /// Deeper inactivity before the calm long-idle posture.
    static let restingInactivityThreshold: TimeInterval = 90 * 60
    /// How long one restless weight-shift beat lasts before easing back to STILL.
    static let restlessCycleDuration: TimeInterval = 2.2
    /// Minimum gap between restless beats — keeps it from ever reading as
    /// nagging or fidgety.
    static let restlessCooldown: TimeInterval = 45

    // MARK: - Figure Motion Engine — gait parameter smoothing + ranges

    /// Per-second exponential convergence rate the engine eases current
    /// gait parameters toward their state's target at.
    static let gaitSmoothingRate: Double = 5.0

    /// Stride is peak-to-peak ground travel of one foot, in reference-box
    /// units — not an amplitude. Rig V2 derives everything else from it.
    static let strideLengthMin: CGFloat = 7
    static let strideLengthMax: CGFloat = 26
    /// Arm swing is now an angle in degrees from vertical, not a length.
    static let armSwingMin: CGFloat = 8
    static let armSwingMax: CGFloat = 26
    static let forwardLeanMin: Double = 1
    static let forwardLeanMax: Double = 7
    /// Residual breathing bob during locomotion. The visible vertical
    /// travel while moving is derived from stance geometry (see
    /// FigureGait.pelvisY), not from these — they only keep a trace of
    /// life in the body at very low intensity.
    static let locomotionBobMin: CGFloat = 0.5
    static let locomotionBobMax: CGFloat = 0.9

    static let stillBreathingBob: CGFloat = 0.6
    static let restingBob: CGFloat = 0.3
    static let risingLeanDegrees: Double = 2
    static let risingBob: CGFloat = 1.0
    static let restlessShiftAmplitude: CGFloat = 1.4
    static let recoveringResidualBob: CGFloat = 1.2

    // MARK: - Figure Motion Engine — cycle rates (Hz, full L/R cycles/sec)

    static let breathingCycleHz: Double = 0.12
    static let restingCycleHz: Double = 0.08
    static let restlessCycleHz: Double = 0.35
    static let risingCycleHz: Double = 0.6
    static let recoveringCycleHz: Double = 0.5
    static let locomotionMinCycleHz: Double = 0.6

    // MARK: - Figure Motion Engine — render throttling
    //
    // LiveAvatar picks a TimelineView refresh interval from these based on
    // the engine's current state, so idle/resting stays cheap and only
    // visible locomotion asks for near-frame-rate updates.

    static let idleFrameInterval: Double = 1.0 / 8
    static let transitionFrameInterval: Double = 1.0 / 24
    static let activeFrameInterval: Double = 1.0 / 55

    // MARK: - Figure Rig V2 — skeleton proportions
    //
    // All in the 120×120 reference box, same as the legacy FigureShape, so
    // the rig and the old static poses stay visually consistent in scale.

    /// Where the implied floor sits. Never rendered outside Figure Lab.
    static let groundY: CGFloat = 112
    /// The ankle joint rides slightly above the floor; the foot segment
    /// bridges the gap. This is the plane leg IK actually targets.
    static let ankleHeight: CGFloat = 3
    static var anklePlaneY: CGFloat { groundY - ankleHeight }

    static let thighLength: CGFloat = 20.5
    static let shinLength: CGFloat = 20.5
    static var legLength: CGFloat { thighLength + shinLength }
    static let toeLength: CGFloat = 5.5

    static let upperArmLength: CGFloat = 15
    static let lowerArmLength: CGFloat = 13

    static let hipSpread: CGFloat = 12
    /// Feet track closer to the midline than the hips do — this is most of
    /// what stops a two-legged line figure reading as a pair of compasses.
    static let stanceWidth: CGFloat = 9
    static let shoulderSpread: CGFloat = 18
    static let torsoLength: CGFloat = 24
    static let neckLength: CGFloat = 12
    static let headOffset: CGFloat = 10
    static let figureHeadRadius: CGFloat = 8

    // MARK: - Figure Rig V2 — gait mechanics

    /// Stance fraction of the cycle. Above 0.5 a foot is always down
    /// (walking); below it a flight phase opens (running).
    static let walkDutyFactor: Double = 0.62
    static let runDutyFactor: Double = 0.34

    /// Baseline hip-to-ankle shortening, as a fraction of full leg length.
    /// Keeps a visible bend in the knee at all times and, just as
    /// importantly, keeps the leg away from full extension where two-bone
    /// IK turns near-singular — there a hair of pelvis movement throws the
    /// knee sideways, which reads as a snap.
    static let baseStanceFlexion: Double = 0.05
    /// Slack held back from the reach budget so rounding and pelvis
    /// obliquity can never push a planted foot off the floor.
    static let pelvisReachMargin: CGFloat = 0.6
    /// Extra midstance knee flexion. Small for walking so the compass
    /// effect dominates and the pelvis peaks at midstance; large for
    /// running so absorption wins and it troughs there instead.
    static let walkStanceKneeFlexion: Double = 0.006
    static let runStanceKneeFlexion: Double = 0.10
    /// Peak extra pelvis rise during flight, at full running.
    static let flightRiseGain: CGFloat = 5.5

    /// Foot lift during swing, as a fraction of stride.
    static let walkSwingHeightRatio: CGFloat = 0.16
    static let runSwingHeightRatio: CGFloat = 0.34

    /// Foot pitch in degrees; positive drives the toe down.
    static let footContactPitch: Double = -6
    static let footToeOffPitch: Double = 18

    // MARK: - Figure Rig V2 — torso, head, arms

    /// Peak pelvis tilt in degrees at full stride.
    static let pelvisObliquityDegrees: Double = 4
    /// How much the shoulder line counter-rotates against the pelvis.
    static let shoulderCounterRotationGain: Double = 0.55
    /// Lateral bow of the spine curve, in units, at full counter-rotation.
    static let spineCurveGain: CGFloat = 2.2

    /// Fraction of pelvis vertical travel the head is allowed to inherit.
    /// Below 1 the head is calmer than the hips, as in real gait; well
    /// above 0 so it still reads as attached to the body.
    static let headFollow: CGFloat = 0.4
    static let shoulderFollow: CGFloat = 0.7

    /// Forearm phase lag behind the upper arm, as a fraction of a cycle.
    static let armLagFraction: Double = 0.06
    static let walkElbowFlexDegrees: Double = 22
    static let runElbowFlexDegrees: Double = 78
    static let elbowFlexVariationDegrees: Double = 10

    // MARK: - Figure Rig V2 — walk/run blend inputs

    static let runBlendCadenceLow: Double = 138
    static let runBlendCadenceHigh: Double = 172
    static let runBlendIntensityLow: Double = 0.55
    static let runBlendIntensityHigh: Double = 0.9

    // MARK: - Figure Rig V2 — postural detail

    /// Lateral pelvis shift used by RISING and RESTLESS to read as a
    /// transfer of weight rather than a step.
    static let risingWeightShift: CGFloat = 1.8
    static let restlessWeightShift: CGFloat = 1.5
    /// RISING settles the pelvis by this much as weight is taken — an
    /// intent cue, deliberately far short of a crouch.
    static let risingPelvisSettle: CGFloat = 1.2

    /// Reduce Motion freezes the cycle here instead of wherever it happened
    /// to be. Phase 0 is the contact frame: one foot forward, one back,
    /// both grounded — the cleanest single frame that still reads as gait.
    static let reducedMotionCanonicalPhase: Double = 0
}
