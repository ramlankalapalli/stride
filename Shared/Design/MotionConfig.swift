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
}
