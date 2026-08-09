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

// MovementTrend lives in Shared/Design/FigureMotionState.swift now (Phase
// 1.1A) — the Figure Motion Engine needs it and that file is shared with
// the widget target, same reason ActivityState lives in Shared/Design.

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
        /// Smoothed steps/minute — Phase 1.1A, feeds the Figure Motion
        /// Engine's locomotion cycle rate. See `updateCadence`.
        let smoothedCadence: Double
    }

    private var samples: [Sample] = []
    private var previousIntensity: Double = 0
    private(set) var movementSessionStartedAt: Date?
    private(set) var lastMeaningfulMovementAt: Date?
    private var smoothedCadence: Double = 0
    private var lastCadenceUpdateAt: Date?

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
        smoothedCadence = 0
        lastCadenceUpdateAt = nil
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

        updateCadence(fresh: fresh, now: now)

        return Snapshot(
            activityState: activity,
            motionIntensity: intensity,
            trend: trend,
            isInMovementSession: movementSessionStartedAt != nil,
            movementSessionStartedAt: movementSessionStartedAt,
            movementSessionDuration: movementSessionStartedAt.map { now.timeIntervalSince($0) },
            lastMeaningfulMovementAt: lastMeaningfulMovementAt,
            inactiveDuration: inactiveDuration,
            smoothedCadence: smoothedCadence
        )
    }

    private mutating func trim(now: Date) {
        samples.removeAll { now.timeIntervalSince($0.date) > MotionConfig.sampleWindow }
    }

    /// Steps/minute, smoothed. Reuses the same sample buffer `record(steps:)`
    /// already fills — no new sensor polling. Resistant to single-step noise
    /// (the instantaneous reading only comes from the two most recent
    /// samples, and even that is blended in via an exponential average
    /// rather than taken raw); responsive enough to visibly react to a real
    /// pace change within a couple of ticks; decays toward 0 on its own once
    /// samples go stale, rather than freezing at the last real value.
    private mutating func updateCadence(fresh: Bool, now: Date) {
        let dt = lastCadenceUpdateAt.map { now.timeIntervalSince($0) } ?? MotionConfig.classifierTickInterval
        lastCadenceUpdateAt = now

        let instantaneous: Double
        if fresh, samples.count >= 2 {
            let newest = samples[samples.count - 1]
            let previous = samples[samples.count - 2]
            let sampleDt = newest.date.timeIntervalSince(previous.date)
            if sampleDt >= MotionConfig.cadenceMinSampleGap {
                instantaneous = max(0, Double(newest.steps - previous.steps) / sampleDt * 60)
            } else {
                instantaneous = smoothedCadence
            }
        } else {
            instantaneous = 0
        }

        let alpha = dt > 0 ? 1 - exp(-MotionConfig.cadenceSmoothingRate * dt) : 0
        smoothedCadence = max(0, smoothedCadence + alpha * (instantaneous - smoothedCadence))
    }
}
