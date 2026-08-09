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

    static let strideLengthMin: CGFloat = 2
    static let strideLengthMax: CGFloat = 11
    static let armSwingMin: CGFloat = 1.5
    static let armSwingMax: CGFloat = 9
    static let forwardLeanMin: Double = 1
    static let forwardLeanMax: Double = 7
    static let locomotionBobMin: CGFloat = 1.5
    static let locomotionBobMax: CGFloat = 6.5

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
    static let activeFrameInterval: Double = 1.0 / 45
}
