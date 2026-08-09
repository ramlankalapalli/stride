import CoreGraphics
import Foundation

// Phase 1.1A / Figure Rig V2 — joint assembly.
//
// FigureGait holds the biomechanics; this file is the part that turns them
// into a set of points to draw. Order matters and is the whole design:
//
//   ground plane → feet → pelvis (from the loaded leg) → knees (IK)
//                       → torso → shoulders → arms (FK) → head
//
// V1 ran that chain in reverse — hips first, feet as an offset from them —
// which is why its feet floated, its legs stretched and its knees never
// really bent. Nothing here is allowed to move a planted foot.
//
// Deliberately still an abstract movement glyph: more joints exist
// internally than are visible, and the rendered silhouette stays a handful
// of strokes (see RigFigureShape in AvatarView.swift).
//
// No CoreMotion, no SwiftUI, no Combine — pure math, testable headless.

/// The full set of joint positions for one instant, in the 120×120
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
    /// Control point for the spine curve between hip centre and neck.
    var spineControl: CGPoint
    var hipCenter: CGPoint
    var leftHip: CGPoint
    var rightHip: CGPoint
    var leftKnee: CGPoint
    var rightKnee: CGPoint
    var leftAnkle: CGPoint
    var rightAnkle: CGPoint
    var leftToe: CGPoint
    var rightToe: CGPoint
    /// Whether each foot is currently bearing weight. Not rendered — used
    /// by tests and the internal-testing Figure Lab readout.
    var leftPlanted: Bool
    var rightPlanted: Bool
}

/// Continuous drive parameters for the rig. There is still no discrete
/// "pose" selector: the postural state machine (`FigureMotionEngine`)
/// decides where these should be heading, and the rig renders wherever they
/// currently are.
struct FigureGaitParameters: Equatable {
    /// 0...1 position within the current gait cycle.
    var phase: Double
    /// Clamped 0...1 read of how hard the figure is currently moving.
    var intensity: Double
    /// Peak-to-peak ground travel of one foot, in reference-box units.
    var strideLength: CGFloat
    /// Informational — steps/minute driving the cycle rate.
    var cadence: Double
    /// Forward lean in degrees, applied as a true rotation about the hip.
    var forwardLean: Double
    /// Peak shoulder swing angle in degrees from vertical.
    var armSwing: CGFloat
    /// Residual breathing amplitude. Visible vertical travel during
    /// locomotion is derived from stance geometry, not from this.
    var verticalBob: CGFloat
    /// 0...1 overall "how alive" — scales gait detail toward stillness.
    var energy: Double
    /// 0 = walking mechanics, 1 = running mechanics. Continuous.
    var runBlend: Double
    /// Lateral pelvis shift, for weight transfer without taking a step.
    var weightShift: CGFloat

    static let neutral = FigureGaitParameters(
        phase: 0, intensity: 0, strideLength: 0, cadence: 0,
        forwardLean: 0, armSwing: 0, verticalBob: 0, energy: 0,
        runBlend: 0, weightShift: 0
    )
}

enum FigureRig {
    /// Matches the legacy FigureShape's reference box exactly, so both
    /// systems scale/centre identically inside any frame.
    static let referenceSize: CGFloat = 120

    private static let centerX: CGFloat = 60

    /// Derive the full joint set for one instant. Pure function — same
    /// input always produces the same output.
    static func joints(for p: FigureGaitParameters) -> FigureJoints {
        let phase = FigureGait.normalizedPhase(p.phase)
        let energy = FigureGait.clamp01(p.energy)
        let runBlend = FigureGait.clamp01(p.runBlend)
        let stride = max(0, p.strideLength)
        let duty = FigureGait.dutyFactor(runBlend: runBlend)
        let swingHeight = FigureGait.swingHeight(stride: stride, runBlend: runBlend)

        // 1. Feet, against the ground. Right leads the cycle; left is half
        //    a cycle behind it, which is what makes the gait alternate.
        let rightFoot = FigureGait.footState(footPhase: phase, duty: duty,
                                             stride: stride, swingHeight: swingHeight)
        let leftFoot = FigureGait.footState(footPhase: phase + 0.5, duty: duty,
                                            stride: stride, swingHeight: swingHeight)

        let rightAnkleBase = CGPoint(x: centerX + MotionConfig.stanceWidth / 2,
                                     y: MotionConfig.anklePlaneY)
        let leftAnkleBase = CGPoint(x: centerX - MotionConfig.stanceWidth / 2,
                                    y: MotionConfig.anklePlaneY)
        let rightAnkle = CGPoint(x: rightAnkleBase.x + rightFoot.offset.x,
                                 y: rightAnkleBase.y + rightFoot.offset.y)
        let leftAnkle = CGPoint(x: leftAnkleBase.x + leftFoot.offset.x,
                                y: leftAnkleBase.y + leftFoot.offset.y)

        // 2. Pelvis, from whichever leg is loaded — never chosen freely, so
        //    a planted foot can't be pulled off the floor.
        let mechanicalPelvisY = FigureGait.pelvisY(phase: phase, duty: duty, stride: stride,
                                                   swingHeight: swingHeight,
                                                   runBlend: runBlend, energy: energy)
        let breathing = -p.verticalBob * CGFloat(0.5 - 0.5 * cos(2 * .pi * phase))
        let pelvisY = mechanicalPelvisY + breathing
        let hipCenter = CGPoint(x: centerX + p.weightShift, y: pelvisY)

        // 3. Pelvis obliquity — the swing-side hip drops a little, so the
        //    hip line stops being a rigid horizontal bar.
        let strideNorm = MotionConfig.strideLengthMax > 0
            ? min(1, Double(stride / MotionConfig.strideLengthMax)) : 0
        let obliquity = MotionConfig.pelvisObliquityDegrees * strideNorm * energy * sin(2 * .pi * phase)
        let (leftHip, rightHip) = spanEndpoints(center: hipCenter,
                                                width: MotionConfig.hipSpread,
                                                tiltDegrees: obliquity)

        // 4. Torso. The head keeps only part of the pelvis's vertical
        //    travel, so it stays the calmest point on the body without
        //    detaching — the spine absorbs the difference, which is exactly
        //    what a spine does.
        let reference = FigureGait.referencePelvisY(stride: stride)
        let deviation = mechanicalPelvisY - reference
        let shoulderY = pelvisY - MotionConfig.torsoLength - deviation * (1 - MotionConfig.shoulderFollow)
        let neckY = pelvisY - MotionConfig.torsoLength - MotionConfig.neckLength
            - deviation * (1 - MotionConfig.headFollow)
        let headY = neckY - MotionConfig.headOffset

        let counterRotation = -MotionConfig.shoulderCounterRotationGain * obliquity
        let shoulderCenter = CGPoint(x: hipCenter.x, y: shoulderY)
        let (leftShoulder, rightShoulder) = spanEndpoints(center: shoulderCenter,
                                                          width: MotionConfig.shoulderSpread,
                                                          tiltDegrees: counterRotation)
        let neck = CGPoint(x: hipCenter.x, y: neckY)
        let headCenter = CGPoint(x: hipCenter.x, y: headY)
        // Bow the spine away from the shoulder twist so the torso reads as
        // a curve responding to the stride, not a drawn rectangle.
        let spineControl = CGPoint(
            x: hipCenter.x + MotionConfig.spineCurveGain * CGFloat(counterRotation / max(1, MotionConfig.pelvisObliquityDegrees)),
            y: (hipCenter.y + neckY) / 2
        )

        // 5. Knees, by IK from hip to the already-placed ankle.
        let rightLeg = FigureGait.solveTwoBone(root: rightHip, target: rightAnkle,
                                               upper: MotionConfig.thighLength,
                                               lower: MotionConfig.shinLength,
                                               bendSign: 1)
        let leftLeg = FigureGait.solveTwoBone(root: leftHip, target: leftAnkle,
                                              upper: MotionConfig.thighLength,
                                              lower: MotionConfig.shinLength,
                                              bendSign: 1)

        // 6. Arms, forward kinematics with a real elbow. Each arm swings
        //    against its same-side leg; the forearm trails slightly so it
        //    stops reading as one rigid pendulum.
        let elbowFlexBase = MotionConfig.walkElbowFlexDegrees
            + runBlend * (MotionConfig.runElbowFlexDegrees - MotionConfig.walkElbowFlexDegrees)
        let rightArm = arm(shoulder: rightShoulder, phase: phase, swingDegrees: Double(p.armSwing),
                           flexBase: elbowFlexBase, energy: energy, sign: 1)
        let leftArm = arm(shoulder: leftShoulder, phase: phase, swingDegrees: Double(p.armSwing),
                          flexBase: elbowFlexBase, energy: energy, sign: -1)

        // 7. Feet. A short segment forward of each ankle — the smallest
        //    mark that reads as contact with a floor. Pitch fades out with
        //    stride so a standing Figure's feet sit flat rather than
        //    rocking through a cycle that isn't going anywhere.
        let pitchScale = MotionConfig.strideLengthMin > 0
            ? min(1, Double(stride / MotionConfig.strideLengthMin)) : 0
        let rightToe = toe(from: rightAnkle, pitchDegrees: rightFoot.pitch * pitchScale)
        let leftToe = toe(from: leftAnkle, pitchDegrees: leftFoot.pitch * pitchScale)

        // 8. Lean, as a true rotation of everything above the pelvis. V1
        //    sheared instead, which skewed the torso and left the hands
        //    behind whenever the elbows moved.
        let lean = p.forwardLean * .pi / 180
        func leaned(_ point: CGPoint) -> CGPoint { rotate(point, about: hipCenter, radians: lean) }

        return FigureJoints(
            head: leaned(headCenter),
            headRadius: MotionConfig.figureHeadRadius,
            neck: leaned(neck),
            shoulderCenter: leaned(shoulderCenter),
            leftShoulder: leaned(leftShoulder),
            rightShoulder: leaned(rightShoulder),
            leftElbow: leaned(leftArm.joint),
            rightElbow: leaned(rightArm.joint),
            leftHand: leaned(leftArm.end),
            rightHand: leaned(rightArm.end),
            spineControl: leaned(spineControl),
            hipCenter: hipCenter,
            leftHip: leftHip,
            rightHip: rightHip,
            leftKnee: leftLeg.joint,
            rightKnee: rightLeg.joint,
            leftAnkle: leftLeg.end,
            rightAnkle: rightLeg.end,
            leftToe: leftToe,
            rightToe: rightToe,
            leftPlanted: leftFoot.planted,
            rightPlanted: rightFoot.planted
        )
    }

    // MARK: - Helpers

    /// Endpoints of a hip or shoulder line of the given width, tilted about
    /// its own centre.
    private static func spanEndpoints(center: CGPoint, width: CGFloat,
                                      tiltDegrees: Double) -> (left: CGPoint, right: CGPoint) {
        let radians = tiltDegrees * .pi / 180
        let dx = width / 2 * CGFloat(cos(radians))
        let dy = width / 2 * CGFloat(sin(radians))
        return (CGPoint(x: center.x - dx, y: center.y - dy),
                CGPoint(x: center.x + dx, y: center.y + dy))
    }

    /// One arm. `sign` is +1 for the right arm, -1 for the left, which is
    /// what puts each arm in opposition to its same-side leg.
    private static func arm(shoulder: CGPoint, phase: Double, swingDegrees: Double,
                            flexBase: Double, energy: Double, sign: Double) -> FigureGait.TwoBoneSolution {
        let swing = -sign * swingDegrees * cos(2 * .pi * phase)
        let lagged = phase - MotionConfig.armLagFraction
        let laggedSwing = -sign * swingDegrees * cos(2 * .pi * lagged)
        let variation = MotionConfig.elbowFlexVariationDegrees * energy
            * (0.5 - 0.5 * cos(2 * .pi * lagged) * sign)
        let flex = flexBase * max(0.25, energy) + variation

        let upperRadians = swing * .pi / 180
        let elbow = CGPoint(x: shoulder.x + MotionConfig.upperArmLength * CGFloat(sin(upperRadians)),
                            y: shoulder.y + MotionConfig.upperArmLength * CGFloat(cos(upperRadians)))
        let forearmRadians = (laggedSwing + flex) * .pi / 180
        let hand = CGPoint(x: elbow.x + MotionConfig.lowerArmLength * CGFloat(sin(forearmRadians)),
                           y: elbow.y + MotionConfig.lowerArmLength * CGFloat(cos(forearmRadians)))
        return FigureGait.TwoBoneSolution(joint: elbow, end: hand)
    }

    private static func toe(from ankle: CGPoint, pitchDegrees: Double) -> CGPoint {
        let radians = pitchDegrees * .pi / 180
        return CGPoint(x: ankle.x + MotionConfig.toeLength * CGFloat(cos(radians)),
                       y: ankle.y + MotionConfig.toeLength * CGFloat(sin(radians)))
    }

    private static func rotate(_ point: CGPoint, about pivot: CGPoint, radians: Double) -> CGPoint {
        guard radians != 0 else { return point }
        let dx = point.x - pivot.x
        let dy = point.y - pivot.y
        let c = CGFloat(cos(radians))
        let s = CGFloat(sin(radians))
        return CGPoint(x: pivot.x + dx * c - dy * s,
                       y: pivot.y + dx * s + dy * c)
    }
}
