import XCTest
import CoreGraphics
@testable import Stride

/// Assembled-rig invariants. Behavioural and geometric only — nothing here
/// asserts an exact rendered position.
final class FigureRigTests: XCTestCase {

    private func walking(intensity: Double = 0.5, phase: Double = 0) -> FigureGaitParameters {
        FigureGaitParameters(phase: phase, intensity: intensity, strideLength: 18, cadence: 110,
                             forwardLean: 3, armSwing: 16, verticalBob: 0.7, energy: max(0.35, intensity),
                             runBlend: 0, weightShift: 0)
    }

    private func running(phase: Double = 0) -> FigureGaitParameters {
        FigureGaitParameters(phase: phase, intensity: 0.97, strideLength: 26, cadence: 172,
                             forwardLean: 7, armSwing: 26, verticalBob: 0.9, energy: 0.97,
                             runBlend: 1, weightShift: 0)
    }

    private func allPoints(_ j: FigureJoints) -> [(String, CGPoint)] {
        [("head", j.head), ("neck", j.neck), ("shoulderCenter", j.shoulderCenter),
         ("leftShoulder", j.leftShoulder), ("rightShoulder", j.rightShoulder),
         ("leftElbow", j.leftElbow), ("rightElbow", j.rightElbow),
         ("leftHand", j.leftHand), ("rightHand", j.rightHand),
         ("spineControl", j.spineControl), ("hipCenter", j.hipCenter),
         ("leftHip", j.leftHip), ("rightHip", j.rightHip),
         ("leftKnee", j.leftKnee), ("rightKnee", j.rightKnee),
         ("leftAnkle", j.leftAnkle), ("rightAnkle", j.rightAnkle),
         ("leftToe", j.leftToe), ("rightToe", j.rightToe)]
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
    }

    // MARK: - Validity

    func test_allJointsFiniteAndInsideReferenceBox() {
        for params in [FigureGaitParameters.neutral, walking(), running()] {
            for step in 0..<120 {
                var p = params
                p.phase = Double(step) / 120
                let j = FigureRig.joints(for: p)
                for (name, point) in allPoints(j) {
                    XCTAssertTrue(point.x.isFinite && point.y.isFinite, "\(name) not finite")
                    XCTAssertTrue(point.x > -40 && point.x < 160, "\(name) far outside box: \(point.x)")
                    XCTAssertTrue(point.y > -40 && point.y < 160, "\(name) far outside box: \(point.y)")
                }
            }
        }
    }

    func test_limbLengthsAreConstantAcrossTheWholeCycle() {
        // V1's limbs stretched with stride; V2's must not, ever.
        for params in [walking(), running()] {
            for step in 0..<120 {
                var p = params
                p.phase = Double(step) / 120
                let j = FigureRig.joints(for: p)
                XCTAssertEqual(distance(j.leftHip, j.leftKnee), MotionConfig.thighLength, accuracy: 0.05)
                XCTAssertEqual(distance(j.leftKnee, j.leftAnkle), MotionConfig.shinLength, accuracy: 0.05)
                XCTAssertEqual(distance(j.rightHip, j.rightKnee), MotionConfig.thighLength, accuracy: 0.05)
                XCTAssertEqual(distance(j.rightKnee, j.rightAnkle), MotionConfig.shinLength, accuracy: 0.05)
                XCTAssertEqual(distance(j.leftShoulder, j.leftElbow), MotionConfig.upperArmLength, accuracy: 0.05)
                XCTAssertEqual(distance(j.leftElbow, j.leftHand), MotionConfig.lowerArmLength, accuracy: 0.05)
                XCTAssertEqual(distance(j.rightShoulder, j.rightElbow), MotionConfig.upperArmLength, accuracy: 0.05)
                XCTAssertEqual(distance(j.rightElbow, j.rightHand), MotionConfig.lowerArmLength, accuracy: 0.05)
            }
        }
    }

    func test_neutralGeometryIsStableAndGrounded() {
        let first = FigureRig.joints(for: .neutral)
        for (name, point) in allPoints(first) {
            XCTAssertTrue(point.x.isFinite && point.y.isFinite, "\(name) not finite")
        }
        // Both feet on the floor, symmetric about the midline, no lean.
        XCTAssertEqual(first.leftAnkle.y, MotionConfig.anklePlaneY, accuracy: 0.01)
        XCTAssertEqual(first.rightAnkle.y, MotionConfig.anklePlaneY, accuracy: 0.01)
        XCTAssertEqual(first.hipCenter.x - first.leftAnkle.x,
                       first.rightAnkle.x - first.hipCenter.x, accuracy: 0.01)
        XCTAssertEqual(first.head.x, first.hipCenter.x, accuracy: 0.01)

        // Phase is meaningless with nothing moving — geometry must not drift.
        var later = FigureGaitParameters.neutral
        later.phase = 0.5
        XCTAssertEqual(first, FigureRig.joints(for: later))
    }

    // MARK: - Gait behaviour

    func test_feetAlternateAndAreNeverBothForward() {
        let p = walking()
        var sawRightLeading = false
        var sawLeftLeading = false
        for step in 0..<120 {
            var q = p
            q.phase = Double(step) / 120
            let j = FigureRig.joints(for: q)
            let rightLead = j.rightAnkle.x - j.hipCenter.x
            let leftLead = j.leftAnkle.x - j.hipCenter.x
            if rightLead > 2 { sawRightLeading = true }
            if leftLead > 2 { sawLeftLeading = true }
            XCTAssertFalse(rightLead > 3 && leftLead > 3, "both feet forward at once")
        }
        XCTAssertTrue(sawRightLeading && sawLeftLeading, "gait did not alternate")
    }

    /// Sampled a half-cycle apart, the two sides must swap roles.
    func test_leftRightGaitIsSymmetric() {
        let p = walking()
        for step in 0..<60 {
            var a = p
            a.phase = Double(step) / 60
            var b = p
            b.phase = a.phase + 0.5
            let ja = FigureRig.joints(for: a)
            let jb = FigureRig.joints(for: b)
            XCTAssertEqual(ja.rightAnkle.x - ja.hipCenter.x,
                           jb.leftAnkle.x - jb.hipCenter.x, accuracy: 0.05)
            XCTAssertEqual(ja.rightAnkle.y, jb.leftAnkle.y, accuracy: 0.05)
            XCTAssertEqual(ja.rightPlanted, jb.leftPlanted)
        }
    }

    func test_plantedFootStaysExactlyOnTheGroundPlane() {
        for params in [walking(), running()] {
            for step in 0..<240 {
                var p = params
                p.phase = Double(step) / 240
                let j = FigureRig.joints(for: p)
                if j.leftPlanted {
                    XCTAssertEqual(j.leftAnkle.y, MotionConfig.anklePlaneY, accuracy: 0.02)
                }
                if j.rightPlanted {
                    XCTAssertEqual(j.rightAnkle.y, MotionConfig.anklePlaneY, accuracy: 0.02)
                }
            }
        }
    }

    /// Each arm swings against its same-side leg. Sampled where the swing
    /// is unambiguous rather than at the crossover points.
    func test_armsOpposeTheirSameSideLeg() {
        let p = walking()
        for step in 0..<120 {
            var q = p
            q.phase = Double(step) / 120
            let j = FigureRig.joints(for: q)
            let rightLeg = j.rightAnkle.x - j.hipCenter.x
            let rightArm = j.rightElbow.x - j.rightShoulder.x
            if abs(rightLeg) > 4, abs(rightArm) > 1 {
                XCTAssertTrue(rightLeg * rightArm < 0,
                              "right arm and right leg moved together at phase \(q.phase)")
            }
            let leftLeg = j.leftAnkle.x - j.hipCenter.x
            let leftArm = j.leftElbow.x - j.leftShoulder.x
            if abs(leftLeg) > 4, abs(leftArm) > 1 {
                XCTAssertTrue(leftLeg * leftArm < 0,
                              "left arm and left leg moved together at phase \(q.phase)")
            }
        }
    }

    func test_jointsMoveContinuously_noTeleports() {
        for params in [walking(), running()] {
            var previous = FigureRig.joints(for: params)
            for step in 1...400 {
                var p = params
                p.phase = Double(step) / 400
                let j = FigureRig.joints(for: p)
                for (a, b) in zip(allPoints(previous), allPoints(j)) {
                    XCTAssertLessThan(distance(a.1, b.1), 2.5,
                                      "\(a.0) jumped between adjacent frames at phase \(p.phase)")
                }
                previous = j
            }
        }
    }

    // MARK: - Walk vs run

    func test_runningDrivesTheKneeHigherThanWalking() {
        func peakKneeLift(_ params: FigureGaitParameters) -> CGFloat {
            var highest: CGFloat = 0
            for step in 0..<120 {
                var p = params
                p.phase = Double(step) / 120
                let j = FigureRig.joints(for: p)
                highest = max(highest, j.hipCenter.y - j.rightKnee.y)
            }
            return highest
        }
        XCTAssertGreaterThan(peakKneeLift(running()), peakKneeLift(walking()))
    }

    func test_runningHoldsTheElbowMoreFlexedThanWalking() {
        func meanElbowAngle(_ params: FigureGaitParameters) -> CGFloat {
            var total: CGFloat = 0
            for step in 0..<60 {
                var p = params
                p.phase = Double(step) / 60
                let j = FigureRig.joints(for: p)
                // Straighter arm ⇒ hand further from shoulder.
                total += distance(j.rightShoulder, j.rightHand)
            }
            return total / 60
        }
        XCTAssertLessThan(meanElbowAngle(running()), meanElbowAngle(walking()),
                          "running should carry a more flexed elbow")
    }

    func test_runningHasFlightFramesAndWalkingDoesNot() {
        func flightFrames(_ params: FigureGaitParameters) -> Int {
            (0..<200).filter { step in
                var p = params
                p.phase = Double(step) / 200
                let j = FigureRig.joints(for: p)
                return !j.leftPlanted && !j.rightPlanted
            }.count
        }
        XCTAssertEqual(flightFrames(walking()), 0)
        XCTAssertGreaterThan(flightFrames(running()), 0)
    }

    // MARK: - Posture

    func test_headIsCalmerThanThePelvis() {
        let p = running()
        var pelvis: [CGFloat] = []
        var head: [CGFloat] = []
        for step in 0..<120 {
            var q = p
            q.phase = Double(step) / 120
            let j = FigureRig.joints(for: q)
            pelvis.append(j.hipCenter.y)
            head.append(j.head.y)
        }
        let pelvisTravel = pelvis.max()! - pelvis.min()!
        let headTravel = head.max()! - head.min()!
        XCTAssertLessThan(headTravel, pelvisTravel, "head should filter pelvis bounce")
        XCTAssertGreaterThan(headTravel, pelvisTravel * 0.15,
                             "head should still move with the body, not float free")
    }

    func test_forwardLeanRotatesTheTorsoAndStaysBounded() {
        var p = walking()
        p.forwardLean = MotionConfig.forwardLeanMax
        let j = FigureRig.joints(for: p)
        let shift = j.head.x - j.hipCenter.x
        XCTAssertGreaterThan(shift, 0, "lean should carry the head forward")
        XCTAssertLessThan(shift, 20)
        // A true rotation keeps the torso's length; a shear would stretch it.
        var upright = p
        upright.forwardLean = 0
        let straight = FigureRig.joints(for: upright)
        XCTAssertEqual(distance(j.hipCenter, j.head),
                       distance(straight.hipCenter, straight.head), accuracy: 0.05)
    }

    func test_weightShiftMovesThePelvisWithoutTakingAStep() {
        var p = FigureGaitParameters.neutral
        p.weightShift = 2
        let shifted = FigureRig.joints(for: p)
        let neutral = FigureRig.joints(for: .neutral)
        XCTAssertEqual(shifted.hipCenter.x - neutral.hipCenter.x, 2, accuracy: 0.01)
        XCTAssertEqual(shifted.leftAnkle.y, neutral.leftAnkle.y, accuracy: 0.01)
        XCTAssertEqual(shifted.rightAnkle.y, neutral.rightAnkle.y, accuracy: 0.01)
    }

    func test_higherIntensityLengthensStrideExcursion() {
        func excursion(_ stride: CGFloat) -> CGFloat {
            var lowest: CGFloat = .greatestFiniteMagnitude
            var highest: CGFloat = -.greatestFiniteMagnitude
            for step in 0..<120 {
                var p = walking()
                p.strideLength = stride
                p.phase = Double(step) / 120
                let j = FigureRig.joints(for: p)
                lowest = min(lowest, j.rightAnkle.x)
                highest = max(highest, j.rightAnkle.x)
            }
            return highest - lowest
        }
        XCTAssertGreaterThan(excursion(MotionConfig.strideLengthMax), excursion(MotionConfig.strideLengthMin))
    }
}
