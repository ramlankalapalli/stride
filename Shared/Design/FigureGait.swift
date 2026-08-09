import CoreGraphics
import Foundation

// Phase 1.1A / Figure Rig V2 — pure gait biomechanics.
//
// Everything here is deterministic math with no SwiftUI, no CoreMotion and
// no notion of how the Figure is drawn. FigureRig consumes these functions
// to place joints; nothing else should need them except tests and the
// internal-testing Figure Lab.
//
// The single organising idea, and the reason V1's feet looked like they
// floated: geometry is derived **from the ground up**, not from the hip
// down. Feet are positioned against a fixed ground plane first; the pelvis
// is then derived from whichever foot is actually carrying weight; knees
// come last, from inverse kinematics. A planted foot therefore cannot drift
// vertically or change speed, because nothing upstream of it is allowed to
// move it.
//
// The Figure is treadmill-style: it never translates across its frame. The
// pelvis stays horizontally anchored and the *ground-relative* foot
// trajectories create the read of locomotion.

enum FigureGait {

    // MARK: - Cycle structure

    /// Wrap any phase into 0..<1.
    static func normalizedPhase(_ phase: Double) -> Double {
        var v = phase.truncatingRemainder(dividingBy: 1)
        if v < 0 { v += 1 }
        return v
    }

    static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }

    /// Fraction of the gait cycle each foot spends on the ground.
    ///
    /// This is the one number that decides whether the Figure is walking or
    /// running, and it's why the walk→run change is a change of *mechanism*
    /// rather than a change of amplitude:
    ///   > 0.5 — the two stance windows overlap, so there is always at least
    ///           one foot down, and a double-support window exists. Walking.
    ///   < 0.5 — the stance windows no longer meet and a gap opens where
    ///           neither foot is down. That gap is a flight phase. Running.
    /// Because it's interpolated continuously, the flight phase is born at
    /// exactly zero width when duty passes 0.5 and widens smoothly. There is
    /// no threshold to snap across.
    static func dutyFactor(runBlend: Double) -> Double {
        let t = clamp01(runBlend)
        return MotionConfig.walkDutyFactor + t * (MotionConfig.runDutyFactor - MotionConfig.walkDutyFactor)
    }

    /// How far each foot swings, peak to peak, in reference-box units.
    static func swingHeight(stride: CGFloat, runBlend: Double) -> CGFloat {
        let ratio = MotionConfig.walkSwingHeightRatio
            + CGFloat(clamp01(runBlend)) * (MotionConfig.runSwingHeightRatio - MotionConfig.walkSwingHeightRatio)
        return stride * ratio
    }

    // MARK: - Foot trajectory

    struct FootState: Equatable {
        /// Offset from this foot's neutral ankle position. y is negative up.
        var offset: CGPoint
        /// True while this foot is bearing weight against the ground.
        var planted: Bool
        /// 0...1 through the stance window; 0 whenever the foot is swinging.
        var stanceProgress: Double
        /// 0...1 through the swing window; 0 whenever the foot is planted.
        var swingProgress: Double
        /// Foot pitch in degrees. Positive pitches the toe down (push-off).
        var pitch: Double
    }

    /// The complete trajectory of one foot, in ground-relative space.
    ///
    /// Stance is deliberately **linear** in phase. On a figure that stays
    /// put, the planted foot's backward travel *is* the implied ground
    /// speed, so it has to be constant — any variation in that speed is
    /// read immediately as the foot slipping. V1 swept the foot
    /// sinusoidally, so its speed varied continuously through the whole
    /// contact, which is exactly why the feet looked like they were sliding.
    ///
    /// Swing eases out, arriving at contact with near-zero horizontal
    /// speed. That matches how a real foot lands (minimal braking) and means
    /// touchdown never shows a visible skid.
    static func footState(footPhase: Double, duty: Double, stride: CGFloat, swingHeight: CGFloat) -> FootState {
        let f = normalizedPhase(footPhase)
        let half = stride / 2

        if duty > 0, f < duty {
            let s = f / duty
            // Constant velocity: front of the stride to the back of it.
            let x = half - stride * CGFloat(s)
            let pitch = MotionConfig.footContactPitch
                + (MotionConfig.footToeOffPitch - MotionConfig.footContactPitch) * s
            return FootState(offset: CGPoint(x: x, y: 0), planted: true,
                             stanceProgress: s, swingProgress: 0, pitch: pitch)
        }

        let denom = 1 - duty
        let sw = denom > 0 ? (f - duty) / denom : 0
        // Ease-out: quick off toe-off, decelerating into touchdown.
        let eased = 1 - (1 - sw) * (1 - sw)
        let x = -half + stride * CGFloat(eased)
        let y = -swingHeight * CGFloat(sin(.pi * sw))
        let pitch = MotionConfig.footToeOffPitch
            + (MotionConfig.footContactPitch - MotionConfig.footToeOffPitch) * sw
        return FootState(offset: CGPoint(x: x, y: y), planted: false,
                         stanceProgress: 0, swingProgress: sw, pitch: pitch)
    }

    // MARK: - Pelvis height

    /// Hip-to-ankle distance for a leg at a given point in its stance.
    ///
    /// Knee flexion during stance is what inverts the vertical rhythm
    /// between walking and running, so it is the second half of the
    /// walk/run mechanism:
    ///   walking — barely any extra flexion, so the compass effect wins and
    ///             the pelvis is *highest* at midstance;
    ///   running — pronounced absorption flexion at midstance, enough to
    ///             overcome the compass effect, so the pelvis is *lowest*
    ///             there and highest in flight.
    static func effectiveLegLength(stanceProgress: Double, runBlend: Double, energy: Double) -> CGFloat {
        let amplitude = MotionConfig.walkStanceKneeFlexion
            + clamp01(runBlend) * (MotionConfig.runStanceKneeFlexion - MotionConfig.walkStanceKneeFlexion)
        let flexion = MotionConfig.baseStanceFlexion
            + amplitude * clamp01(energy) * sin(.pi * stanceProgress)
        return MotionConfig.legLength * CGFloat(1 - flexion)
    }

    /// Vertical rise added while neither foot is down. Scales to zero as the
    /// duty factor approaches 0.5, so a flight phase always begins from
    /// nothing rather than appearing at some finite height.
    static func flightRise(duty: Double, energy: Double) -> CGFloat {
        guard duty < 0.5 else { return 0 }
        let openness = (0.5 - duty) / 0.5
        return MotionConfig.flightRiseGain * CGFloat(openness * clamp01(energy))
    }

    /// 0...1 through whichever flight window `phase` falls in, or nil when a
    /// foot is down. Flight windows are [duty, 0.5) and [0.5 + duty, 1).
    static func flightProgress(phase: Double, duty: Double) -> Double? {
        guard duty < 0.5 else { return nil }
        let phi = normalizedPhase(phase)
        let width = 0.5 - duty
        if phi >= duty, phi < 0.5 { return (phi - duty) / width }
        if phi >= 0.5 + duty { return (phi - (0.5 + duty)) / width }
        return nil
    }

    /// Pelvis height, derived entirely from whatever is carrying weight.
    ///
    /// This is what guarantees ground contact. The pelvis is never given a
    /// height of its own that the legs then have to try to satisfy — it is
    /// placed exactly where the stance leg can reach, so the planted foot
    /// can never be pulled off the ground or stretched to meet it. When
    /// both feet are down, the lower of the two candidate heights wins, so
    /// both legs stay within reach.
    static func pelvisY(phase: Double, duty: Double, stride: CGFloat, runBlend: Double, energy: Double) -> CGFloat {
        let phi = normalizedPhase(phase)
        let half = stride / 2
        var lowest: CGFloat?

        for footPhase in [phi, normalizedPhase(phi + 0.5)] {
            guard duty > 0, footPhase < duty else { continue }
            let s = footPhase / duty
            let dx = abs(half - stride * CGFloat(s))
            let leg = effectiveLegLength(stanceProgress: s, runBlend: runBlend, energy: energy)
            let vertical = sqrt(max(0, leg * leg - dx * dx))
            let candidate = MotionConfig.anklePlaneY - vertical
            lowest = max(lowest ?? candidate, candidate)
        }

        if let lowest { return lowest }

        // Flight. Both ends of this window are a foot at full stride
        // extension with no absorption flexion, so the arc starts and ends
        // at exactly the height stance hands over — continuous by
        // construction, in both directions.
        let leg = effectiveLegLength(stanceProgress: 0, runBlend: runBlend, energy: energy)
        let base = MotionConfig.anklePlaneY - sqrt(max(0, leg * leg - half * half))
        let s = flightProgress(phase: phi, duty: duty) ?? 0
        return base - flightRise(duty: duty, energy: energy) * CGFloat(sin(.pi * s))
    }

    /// The height the pelvis sits at with no oscillation at all — the anchor
    /// head stabilisation filters against.
    static func referencePelvisY(stride: CGFloat) -> CGFloat {
        let leg = MotionConfig.legLength * CGFloat(1 - MotionConfig.baseStanceFlexion)
        let half = stride / 2
        return MotionConfig.anklePlaneY - sqrt(max(0, leg * leg - half * half))
    }

    // MARK: - Inverse kinematics

    struct TwoBoneSolution: Equatable {
        /// Knee or elbow.
        var joint: CGPoint
        /// Ankle or hand. Equals the requested target unless it was out of
        /// reach, in which case it is pulled to the reachable limit so both
        /// segments keep their exact lengths.
        var end: CGPoint
    }

    /// Analytic two-bone IK. Segment lengths are preserved exactly — the
    /// limb can never stretch, which was V1's other structural problem
    /// (its knee sat at the midpoint of hip→foot, so the leg was always a
    /// straight line whose length grew with stride).
    ///
    /// `bendSign` picks which side the joint breaks toward: +1 puts it
    /// forward (knees), -1 puts it back (elbows). It never flips, so the
    /// joint cannot invert.
    static func solveTwoBone(root: CGPoint, target: CGPoint,
                             upper: CGFloat, lower: CGFloat,
                             bendSign: CGFloat) -> TwoBoneSolution {
        let dx = target.x - root.x
        let dy = target.y - root.y
        let rawDistance = sqrt(dx * dx + dy * dy)

        guard rawDistance > 0.0001 else {
            // Degenerate: target sits on the root. Drop the limb straight
            // down so the result is still well formed.
            let joint = CGPoint(x: root.x, y: root.y + upper)
            return TwoBoneSolution(joint: joint, end: CGPoint(x: root.x, y: root.y + upper + lower))
        }

        let ux = dx / rawDistance
        let uy = dy / rawDistance
        let maxReach = upper + lower - 0.0001
        let minReach = max(abs(upper - lower) + 0.0001, 0.0001)
        let distance = min(max(rawDistance, minReach), maxReach)

        let end = CGPoint(x: root.x + ux * distance, y: root.y + uy * distance)
        let a = (distance * distance + upper * upper - lower * lower) / (2 * distance)
        let h = sqrt(max(0, upper * upper - a * a))
        let baseX = root.x + ux * a
        let baseY = root.y + uy * a
        // Perpendicular to the root→end direction; +1 is forward in the
        // Figure's y-down reference box.
        let joint = CGPoint(x: baseX + uy * h * bendSign,
                            y: baseY - ux * h * bendSign)
        return TwoBoneSolution(joint: joint, end: end)
    }

    // MARK: - Walk / run blend

    /// How far into running the Figure currently is, from real signals.
    /// Cadence decides most of it; intensity gates it so a brief burst of
    /// fast steps at low effort can't tip the whole rig into running.
    static func runBlend(cadence: Double, intensity: Double) -> Double {
        let cadenceSpan = MotionConfig.runBlendCadenceHigh - MotionConfig.runBlendCadenceLow
        let byCadence = cadenceSpan > 0
            ? clamp01((cadence - MotionConfig.runBlendCadenceLow) / cadenceSpan)
            : 0
        let intensitySpan = MotionConfig.runBlendIntensityHigh - MotionConfig.runBlendIntensityLow
        let byIntensity = intensitySpan > 0
            ? clamp01((intensity - MotionConfig.runBlendIntensityLow) / intensitySpan)
            : 0
        return byCadence * byIntensity
    }
}
