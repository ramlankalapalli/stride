import XCTest
import CoreGraphics
@testable import Stride

final class FigureRigTests: XCTestCase {

    private func assertFinite(_ point: CGPoint, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(point.x.isFinite, "\(label).x not finite", file: file, line: line)
        XCTAssertTrue(point.y.isFinite, "\(label).y not finite", file: file, line: line)
    }

    private func assertAllFinite(_ joints: FigureJoints, file: StaticString = #filePath, line: UInt = #line) {
        assertFinite(joints.head, "head", file: file, line: line)
        assertFinite(joints.neck, "neck", file: file, line: line)
        assertFinite(joints.shoulderCenter, "shoulderCenter", file: file, line: line)
        assertFinite(joints.leftShoulder, "leftShoulder", file: file, line: line)
        assertFinite(joints.rightShoulder, "rightShoulder", file: file, line: line)
        assertFinite(joints.leftElbow, "leftElbow", file: file, line: line)
        assertFinite(joints.rightElbow, "rightElbow", file: file, line: line)
        assertFinite(joints.leftHand, "leftHand", file: file, line: line)
        assertFinite(joints.rightHand, "rightHand", file: file, line: line)
        assertFinite(joints.hipCenter, "hipCenter", file: file, line: line)
        assertFinite(joints.leftHip, "leftHip", file: file, line: line)
        assertFinite(joints.rightHip, "rightHip", file: file, line: line)
        assertFinite(joints.leftKnee, "leftKnee", file: file, line: line)
        assertFinite(joints.rightKnee, "rightKnee", file: file, line: line)
        assertFinite(joints.leftFoot, "leftFoot", file: file, line: line)
        assertFinite(joints.rightFoot, "rightFoot", file: file, line: line)
    }

    func test_neutralGeometry_isFiniteAndStable() {
        let joints = FigureRig.joints(for: .neutral)
        assertAllFinite(joints)
        // Zero energy/stride/lean/bob means both feet sit directly under
        // their hip, not swung to either side.
        XCTAssertEqual(joints.leftFoot.x, joints.leftHip.x)
        XCTAssertEqual(joints.rightFoot.x, joints.rightHip.x)
        XCTAssertEqual(joints.forwardLeanIsZero, true)
    }

    func test_zeroMovement_producesStableGeometryAcrossPhase() {
        // Even with phase varying, zero-amplitude parameters must produce
        // identical, stable geometry — phase is meaningless at energy 0.
        var params = FigureGaitParameters.neutral
        let first = FigureRig.joints(for: params)
        params.phase = 0.5
        let second = FigureRig.joints(for: params)
        XCTAssertEqual(first, second)
    }

    func test_gaitAlternatesLeftAndRight() {
        var params = FigureGaitParameters.neutral
        params.strideLength = 10
        params.energy = 0.8

        // Quarter and three-quarter cycle — the two points of maximum
        // (opposite-sign) swing excursion. 0.0/0.5 are both zero-crossings
        // of sin() and would coincide, which isn't what this test means to
        // check.
        params.phase = 0.25
        let a = FigureRig.joints(for: params)
        params.phase = 0.75
        let b = FigureRig.joints(for: params)

        // Half a cycle later, the leg that was forward is now back — the
        // two phases must not produce the same foot placement.
        XCTAssertNotEqual(a.leftFoot.x, b.leftFoot.x)
        XCTAssertNotEqual(a.rightFoot.x, b.rightFoot.x)
        // And at any single instant, the two feet should generally differ
        // (opposite phase), except at the rare crossover point — verify at
        // a non-crossover phase.
        XCTAssertNotEqual(a.leftFoot.x, a.rightFoot.x)
    }

    func test_higherIntensity_increasesStrideExcursion() {
        var low = FigureGaitParameters.neutral
        low.strideLength = 2
        low.phase = 0.25 // peak excursion for sin(phase*2pi)

        var high = FigureGaitParameters.neutral
        high.strideLength = 11
        high.phase = 0.25

        let lowJoints = FigureRig.joints(for: low)
        let highJoints = FigureRig.joints(for: high)

        let lowExcursion = abs(lowJoints.leftFoot.x - lowJoints.leftHip.x)
        let highExcursion = abs(highJoints.leftFoot.x - highJoints.leftHip.x)
        XCTAssertGreaterThan(highExcursion, lowExcursion)
    }

    func test_forwardLean_staysBounded() {
        var params = FigureGaitParameters.neutral
        params.forwardLean = MotionConfig.forwardLeanMax
        let joints = FigureRig.joints(for: params)
        assertAllFinite(joints)
        // Head should shift forward (positive x) relative to hip when
        // leaning, and by a bounded, sane amount for this reference box.
        let shift = joints.head.x - joints.hipCenter.x
        XCTAssertGreaterThan(shift, 0)
        XCTAssertLessThan(shift, 20)
    }
}

private extension FigureJoints {
    /// Sanity check used only by the neutral-geometry test: with zero lean,
    /// head.x should sit exactly above hipCenter.x.
    var forwardLeanIsZero: Bool { head.x == hipCenter.x }
}
