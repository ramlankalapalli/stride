import CoreGraphics

// Phase 1.1A — Figure Motion Engine, part 1: the rig.
//
// A minimal procedural joint skeleton for the Figure. Replaces the idea of
// "poses" with a small set of joints whose positions are a pure function of
// continuous gait parameters — so WALKING/BRISK/RUNNING are never separate
// artwork, just different coordinates in this same parameter space.
//
// Deliberately not anatomically detailed: this stays a minimal athletic line
// sculpture, matching the existing hand-drawn Figure's proportions (same
// 120×120 reference box, same rough joint placements as the old FigureShape
// standing pose) rather than a realistic body rig.
//
// No CoreMotion, no SwiftUI, no Combine — pure math, unit-testable headless.

/// The full set of rendered joint positions for one instant, in the 120×120
/// reference box (same convention as the legacy `FigureShape`).
struct FigureJoints: Equatable {
    var head: CGPoint
    var headRadius: CGFloat
    var neck: CGPoint
    var shoulderCenter: CGPoint
    var leftShoulder: CGPoint
    var rightShoulder: CGPoint
    var leftElbow: CGPoint
    var rightElbow: CGPoint
    var leftHand: CGPoint
    var rightHand: CGPoint
    var hipCenter: CGPoint
    var leftHip: CGPoint
    var rightHip: CGPoint
    var leftKnee: CGPoint
    var rightKnee: CGPoint
    var leftFoot: CGPoint
    var rightFoot: CGPoint
}

/// Continuous drive parameters for the rig. These are the *only* inputs that
/// change what gets drawn — there is no discrete "pose" selector here. The
/// postural state machine (`FigureMotionEngine`) is what decides where these
/// parameters should be heading at any moment; the rig just renders them.
struct FigureGaitParameters: Equatable {
    /// 0...1 position within the current gait cycle. Meaningless at energy 0.
    var phase: Double
    /// Clamped 0...1 read of how hard the figure is currently moving.
    var intensity: Double
    /// How far each foot swings from center, in reference-box units.
    var strideLength: CGFloat
    /// Informational — steps/minute driving the cycle rate during locomotion.
    var cadence: Double
    /// Forward lean, in degrees, sheared around the hip.
    var forwardLean: Double
    /// How far each hand swings from its shoulder, in reference-box units.
    var armSwing: CGFloat
    /// Vertical bob amplitude, in reference-box units.
    var verticalBob: CGFloat
    /// 0...1 overall "how alive" — scales knee bend / gait crispness.
    var energy: Double

    static let neutral = FigureGaitParameters(
        phase: 0, intensity: 0, strideLength: 0, cadence: 0,
        forwardLean: 0, armSwing: 0, verticalBob: 0, energy: 0
    )
}

enum FigureRig {
    /// Matches the legacy FigureShape's reference box exactly, so both
    /// systems scale/center identically inside any frame.
    static let referenceSize: CGFloat = 120

    private static let centerX: CGFloat = 60
    private static let hipY: CGFloat = 68
    private static let shoulderY: CGFloat = 44
    private static let neckY: CGFloat = 32
    private static let headCenterY: CGFloat = 22
    private static let headRadius: CGFloat = 8

    private static let shoulderSpread: CGFloat = 18
    private static let hipSpread: CGFloat = 12
    private static let upperArmLength: CGFloat = 16
    private static let lowerArmLength: CGFloat = 14
    private static let thighLength: CGFloat = 22
    private static let shinLength: CGFloat = 22
    /// How much extra knee bend energy adds at the peak of a stride —
    /// a hint of athletic drive at high energy, never a deep crouch.
    private static let maxKneeLift: CGFloat = 8

    /// Derive the full joint set for one instant from continuous parameters.
    /// Pure function — same input always produces the same output.
    static func joints(for p: FigureGaitParameters) -> FigureJoints {
        let cycle = p.phase * 2 * .pi

        // Legs swing opposite each other; the bob is a double-frequency lift
        // (both feet pass under the hip twice per full stride cycle).
        let leftLegSwing = CGFloat(sin(cycle)) * p.strideLength
        let rightLegSwing = CGFloat(sin(cycle + .pi)) * p.strideLength
        let bob = CGFloat(abs(cos(cycle))) * p.verticalBob

        // Arms swing opposite their same-side leg.
        let leftArmSwing = CGFloat(sin(cycle + .pi)) * p.armSwing
        let rightArmSwing = CGFloat(sin(cycle)) * p.armSwing

        let leanRadians = p.forwardLean * .pi / 180

        let hipCenter = CGPoint(x: centerX, y: hipY - bob)
        let shoulderCenter = CGPoint(x: centerX, y: shoulderY - bob)
        let neck = CGPoint(x: centerX, y: neckY - bob)
        let headCenter = CGPoint(x: centerX, y: headCenterY - bob)

        let leftShoulder = CGPoint(x: shoulderCenter.x - shoulderSpread / 2, y: shoulderCenter.y)
        let rightShoulder = CGPoint(x: shoulderCenter.x + shoulderSpread / 2, y: shoulderCenter.y)
        let leftHip = CGPoint(x: hipCenter.x - hipSpread / 2, y: hipCenter.y)
        let rightHip = CGPoint(x: hipCenter.x + hipSpread / 2, y: hipCenter.y)

        let leftElbow = CGPoint(x: leftShoulder.x + leftArmSwing * 0.6, y: leftShoulder.y + upperArmLength)
        let rightElbow = CGPoint(x: rightShoulder.x + rightArmSwing * 0.6, y: rightShoulder.y + upperArmLength)
        let leftHand = CGPoint(x: leftElbow.x + leftArmSwing, y: leftElbow.y + lowerArmLength)
        let rightHand = CGPoint(x: rightElbow.x + rightArmSwing, y: rightElbow.y + lowerArmLength)

        let kneeLift = CGFloat(p.energy) * maxKneeLift
        let leftKnee = CGPoint(
            x: leftHip.x + leftLegSwing * 0.5,
            y: leftHip.y + thighLength - kneeLift * CGFloat(abs(sin(cycle)))
        )
        let rightKnee = CGPoint(
            x: rightHip.x + rightLegSwing * 0.5,
            y: rightHip.y + thighLength - kneeLift * CGFloat(abs(sin(cycle + .pi)))
        )
        let leftFoot = CGPoint(x: leftHip.x + leftLegSwing, y: leftKnee.y + shinLength)
        let rightFoot = CGPoint(x: rightHip.x + rightLegSwing, y: rightKnee.y + shinLength)

        func lean(_ point: CGPoint) -> CGPoint {
            // Shear around the hip: points above the hip move forward with
            // lean, points at/below it don't — this reads as the torso
            // leaning while the feet stay planted, not the whole figure
            // sliding sideways.
            let dy = hipCenter.y - point.y
            guard dy > 0 else { return point }
            return CGPoint(x: point.x + dy * CGFloat(sin(leanRadians)), y: point.y)
        }

        return FigureJoints(
            head: lean(headCenter),
            headRadius: headRadius,
            neck: lean(neck),
            shoulderCenter: lean(shoulderCenter),
            leftShoulder: lean(leftShoulder),
            rightShoulder: lean(rightShoulder),
            leftElbow: lean(leftElbow),
            rightElbow: lean(rightElbow),
            leftHand: lean(leftHand),
            rightHand: lean(rightHand),
            hipCenter: hipCenter,
            leftHip: leftHip,
            rightHip: rightHip,
            leftKnee: leftKnee,
            rightKnee: rightKnee,
            leftFoot: leftFoot,
            rightFoot: rightFoot
        )
    }
}
