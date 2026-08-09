import Foundation

// Foundation-hardening pass — Phase 1.0.5.
//
// The idle/walking/active + intensity math used to live inline inside
// StepProvider, tangled up with the CMPedometer callbacks and the Timer
// that drove it — impossible to unit test without hardware. This pulls the
// pure classification math out into its own value type: feed it
// (timestamp, cumulative step count) samples, call `evaluate`, get a
// Snapshot back. No CoreMotion, no SwiftUI, no Combine, no Timer.
//
// This phase only builds the *signals* — lastMeaningfulMovementAt,
// inactiveDuration, movement sessions with hysteresis, and a rising/
// steady/falling trend — for a future Momentum/Figure phase to consume.
// Nothing here is wired into any view yet.

enum MovementTrend {
    case rising, steady, falling
}

struct MovementClassifier {

    struct Sample {
        let date: Date
        let steps: Int
    }

    struct Snapshot {
        let activityState: ActivityState
        let motionIntensity: Double
        let trend: MovementTrend
        let isInMovementSession: Bool
        let movementSessionStartedAt: Date?
        let movementSessionDuration: TimeInterval?
        let lastMeaningfulMovementAt: Date?
        /// nil means "no meaningful movement observed yet this session" —
        /// distinct from "0 seconds ago".
        let inactiveDuration: TimeInterval?
    }

    private var samples: [Sample] = []
    private var previousIntensity: Double = 0
    private(set) var movementSessionStartedAt: Date?
    private(set) var lastMeaningfulMovementAt: Date?

    /// Record a new cumulative step reading from the live pedometer feed.
    mutating func record(steps: Int, at date: Date = Date()) {
        samples.append(Sample(date: date, steps: steps))
        trim(now: date)
    }

    /// Drop everything and start clean — used on a midnight rebase so
    /// yesterday's cadence/session never bleeds into today.
    mutating func reset() {
        samples.removeAll()
        previousIntensity = 0
        movementSessionStartedAt = nil
        lastMeaningfulMovementAt = nil
    }

    /// Re-derive current state as of `now`. Call on the classifier timer
    /// tick, and after `record(steps:)`.
    @discardableResult
    mutating func evaluate(now: Date = Date()) -> Snapshot {
        trim(now: now)

        let stepsInWindow: Int
        let fresh: Bool
        if let newest = samples.last, let oldest = samples.first,
           now.timeIntervalSince(newest.date) < MotionConfig.sampleStaleness {
            stepsInWindow = newest.steps - oldest.steps
            fresh = true
        } else {
            stepsInWindow = 0
            fresh = false
        }

        let activity: ActivityState
        if !fresh {
            activity = .idle
        } else if stepsInWindow >= MotionConfig.activeStepThreshold {
            activity = .active
        } else if stepsInWindow >= MotionConfig.walkingStepThreshold {
            activity = .walking
        } else {
            activity = .idle
        }

        let intensity = fresh
            ? min(1, max(0, (Double(stepsInWindow) - MotionConfig.intensityFloorSteps) / MotionConfig.intensityRangeSteps))
            : 0

        let delta = intensity - previousIntensity
        let trend: MovementTrend
        if delta > MotionConfig.trendHysteresis { trend = .rising }
        else if delta < -MotionConfig.trendHysteresis { trend = .falling }
        else { trend = .steady }
        previousIntensity = intensity

        // Session hysteresis: a small but real step count (re)starts or
        // extends a session; only a *sustained* pause ends it. Short gaps
        // (a stoplight, tying a shoe) don't instantly end the session, even
        // though the pose-level activityState above already went idle.
        if stepsInWindow >= MotionConfig.sessionStartStepThreshold {
            lastMeaningfulMovementAt = now
            if movementSessionStartedAt == nil { movementSessionStartedAt = now }
        }
        if let lastMove = lastMeaningfulMovementAt,
           now.timeIntervalSince(lastMove) > MotionConfig.sessionEndInactivity {
            movementSessionStartedAt = nil
        }

        let inactiveDuration = lastMeaningfulMovementAt.map { now.timeIntervalSince($0) }

        return Snapshot(
            activityState: activity,
            motionIntensity: intensity,
            trend: trend,
            isInMovementSession: movementSessionStartedAt != nil,
            movementSessionStartedAt: movementSessionStartedAt,
            movementSessionDuration: movementSessionStartedAt.map { now.timeIntervalSince($0) },
            lastMeaningfulMovementAt: lastMeaningfulMovementAt,
            inactiveDuration: inactiveDuration
        )
    }

    private mutating func trim(now: Date) {
        samples.removeAll { now.timeIntervalSince($0.date) > MotionConfig.sampleWindow }
    }
}
