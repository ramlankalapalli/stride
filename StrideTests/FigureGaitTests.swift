import XCTest
import CoreGraphics
@testable import Stride

/// Biomechanical invariants, tested on the pure math only — no rendering,
/// no pixel assertions. These are the properties that make the Figure look
/// grounded; if one of them breaks, it will look wrong on device.
final class FigureGaitTests: XCTestCase {

    private let samples = 200
    private func phases(_ count: Int? = nil) -> [Double] {
        let n = count ?? samples
        return (0..<n).map { Double($0) / Double(n) }
    }

    // MARK: - Duty factor / walk-run structure

    func test_walkDuty_keepsAFootDownAtAllTimes() {
        let duty = FigureGait.dutyFactor(runBlend: 0)
        XCTAssertGreaterThan(duty, 0.5, "walking must have overlapping stance windows")
        for phi in phases() {
            let right = FigureGait.footState(footPhase: phi, duty: duty, stride: 16, swingHeight: 3)
            let left = FigureGait.footState(footPhase: phi + 0.5, duty: duty, stride: 16, swingHeight: 3)
            XCTAssertTrue(right.planted || left.planted, "walk had no foot down at phase \(phi)")
        }
    }

    func test_runDuty_producesARealFlightPhase() {
        let duty = FigureGait.dutyFactor(runBlend: 1)
        XCTAssertLessThan(duty, 0.5, "running must open a gap between stance windows")
        let flightFrames = phases().filter { phi in
            let right = FigureGait.footState(footPhase: phi, duty: duty, stride: 24, swingHeight: 8)
            let left = FigureGait.footState(footPhase: phi + 0.5, duty: duty, stride: 24, swingHeight: 8)
            return !right.planted && !left.planted
        }
        XCTAssertFalse(flightFrames.isEmpty, "running produced no flight frames")
    }

    func test_dutyFactor_movesContinuouslyAcrossTheWalkRunRegion() {
        // No step anywhere in the blend — this is what guarantees there is
        // no visible snap when the Figure transitions into running.
        var previous = FigureGait.dutyFactor(runBlend: 0)
        for i in 1...200 {
            let duty = FigureGait.dutyFactor(runBlend: Double(i) / 200)
            XCTAssertLessThan(abs(duty - previous), 0.01)
            previous = duty
        }
    }

    func test_flightRise_vanishesAsDutyApproachesHalf() {
        XCTAssertEqual(FigureGait.flightRise(duty: 0.5, energy: 1), 0)
        XCTAssertEqual(FigureGait.flightRise(duty: 0.62, energy: 1), 0)
        XCTAssertGreaterThan(FigureGait.flightRise(duty: 0.34, energy: 1), 0)
    }

    // MARK: - Foot planting

    func test_plantedFoot_neverLeavesTheGround() {
        let duty = FigureGait.dutyFactor(runBlend: 0)
        for phi in phases() {
            let foot = FigureGait.footState(footPhase: phi, duty: duty, stride: 18, swingHeight: 4)
            if foot.planted {
                XCTAssertEqual(foot.offset.y, 0, accuracy: 0.0001,
                               "planted foot lifted off the ground at phase \(phi)")
            }
        }
    }

    /// The anti-slide invariant. A planted foot on a Figure that stays put
    /// has to travel at a constant speed, because that speed *is* the
    /// implied ground speed — any variation reads as the foot skidding.
    func test_plantedFoot_travelsAtConstantSpeed() {
        let duty = FigureGait.dutyFactor(runBlend: 0)
        let stride: CGFloat = 18
        let step = 0.001
        var speeds: [CGFloat] = []
        var phi = 0.002
        while phi < duty - 0.002 {
            let a = FigureGait.footState(footPhase: phi, duty: duty, stride: stride, swingHeight: 4)
            let b = FigureGait.footState(footPhase: phi + step, duty: duty, stride: stride, swingHeight: 4)
            guard a.planted, b.planted else { phi += step; continue }
            speeds.append((b.offset.x - a.offset.x) / CGFloat(step))
            phi += step
        }
        XCTAssertFalse(speeds.isEmpty)
        let first = speeds[0]
        XCTAssertLessThan(first, 0, "stance foot must travel backwards")
        for speed in speeds {
            XCTAssertEqual(speed, first, accuracy: 0.01, "stance speed varied — the foot will look like it is sliding")
        }
    }

    func test_footPosition_isContinuousAcrossStanceSwingBoundary() {
        for runBlend in [0.0, 0.5, 1.0] {
            let duty = FigureGait.dutyFactor(runBlend: runBlend)
            let stride: CGFloat = 20
            let height = FigureGait.swingHeight(stride: stride, runBlend: runBlend)
            for boundary in [duty, 1.0] {
                let before = FigureGait.footState(footPhase: boundary - 0.0005, duty: duty, stride: stride, swingHeight: height)
                let after = FigureGait.footState(footPhase: boundary + 0.0005, duty: duty, stride: stride, swingHeight: height)
                XCTAssertEqual(before.offset.x, after.offset.x, accuracy: 0.15,
                               "foot teleported at boundary \(boundary), runBlend \(runBlend)")
                XCTAssertEqual(before.offset.y, after.offset.y, accuracy: 0.15)
            }
        }
    }

    func test_footTouchesDownWithoutHorizontalSkid() {
        // Swing eases out, so the foot arrives with near-zero horizontal
        // speed rather than landing already moving.
        let duty = FigureGait.dutyFactor(runBlend: 0)
        let a = FigureGait.footState(footPhase: 0.99, duty: duty, stride: 18, swingHeight: 4)
        let b = FigureGait.footState(footPhase: 0.999, duty: duty, stride: 18, swingHeight: 4)
        let landingSpeed = abs((b.offset.x - a.offset.x) / 0.009)
        let stanceSpeed = 18.0 / duty
        XCTAssertLessThan(Double(landingSpeed), stanceSpeed * 0.5,
                          "foot is still moving fast at touchdown — it will skid")
    }

    // MARK: - Pelvis

    func test_pelvisIsAlwaysReachableByALoadedLeg() {
        // If this fails, a planted foot is being stretched away from the
        // floor — the single worst failure mode for this rig.
        for runBlend in [0.0, 0.35, 0.7, 1.0] {
            let duty = FigureGait.dutyFactor(runBlend: runBlend)
            let stride: CGFloat = 22
            for phi in phases(120) {
                let pelvis = FigureGait.pelvisY(phase: phi, duty: duty, stride: stride,
                                                runBlend: runBlend, energy: 1)
                for footPhase in [phi, phi + 0.5] {
                    let foot = FigureGait.footState(footPhase: footPhase, duty: duty,
                                                    stride: stride, swingHeight: 4)
                    guard foot.planted else { continue }
                    let dx = foot.offset.x
                    let dy = MotionConfig.anklePlaneY - pelvis
                    let distance = sqrt(dx * dx + dy * dy)
                    XCTAssertLessThanOrEqual(distance, MotionConfig.legLength + 0.001,
                                             "stance leg over-extended at phase \(phi), runBlend \(runBlend)")
                }
            }
        }
    }

    func test_walkPelvisPeaksAtMidstance_runPelvisTroughsThere() {
        // The mechanical inversion that makes running running, rather than
        // a faster walk with bigger numbers.
        let walkDuty = FigureGait.dutyFactor(runBlend: 0)
        let walkMid = FigureGait.pelvisY(phase: walkDuty / 2, duty: walkDuty, stride: 18, runBlend: 0, energy: 1)
        let walkContact = FigureGait.pelvisY(phase: 0, duty: walkDuty, stride: 18, runBlend: 0, energy: 1)
        XCTAssertLessThan(walkMid, walkContact, "walking pelvis should be highest at midstance")

        let runDuty = FigureGait.dutyFactor(runBlend: 1)
        let runMid = FigureGait.pelvisY(phase: runDuty / 2, duty: runDuty, stride: 26, runBlend: 1, energy: 1)
        let runContact = FigureGait.pelvisY(phase: 0, duty: runDuty, stride: 26, runBlend: 1, energy: 1)
        XCTAssertGreaterThan(runMid, runContact, "running pelvis should be lowest at midstance (absorption)")
    }

    func test_pelvisIsContinuousAcrossFlightBoundaries() {
        let runBlend = 1.0
        let duty = FigureGait.dutyFactor(runBlend: runBlend)
        for boundary in [duty, 0.5, 0.5 + duty] {
            let before = FigureGait.pelvisY(phase: boundary - 0.0005, duty: duty, stride: 26, runBlend: runBlend, energy: 1)
            let after = FigureGait.pelvisY(phase: boundary + 0.0005, duty: duty, stride: 26, runBlend: runBlend, energy: 1)
            XCTAssertEqual(before, after, accuracy: 0.2, "pelvis jumped at flight boundary \(boundary)")
        }
    }

    func test_zeroEnergy_producesAFlatPelvis() {
        let duty = FigureGait.dutyFactor(runBlend: 0)
        let baseline = FigureGait.pelvisY(phase: 0, duty: duty, stride: 0, runBlend: 0, energy: 0)
        for phi in phases(60) {
            let y = FigureGait.pelvisY(phase: phi, duty: duty, stride: 0, runBlend: 0, energy: 0)
            XCTAssertEqual(y, baseline, accuracy: 0.0001)
        }
    }

    func test_verticalTravelStaysRestrained() {
        // Constraint: mechanically-derived motion must not read as bouncing.
        for (runBlend, stride, limit) in [(0.0, CGFloat(20), CGFloat(3)), (1.0, CGFloat(26), CGFloat(9))] {
            let duty = FigureGait.dutyFactor(runBlend: runBlend)
            let values = phases(120).map {
                FigureGait.pelvisY(phase: $0, duty: duty, stride: stride, runBlend: runBlend, energy: 1)
            }
            let travel = values.max()! - values.min()!
            XCTAssertLessThan(travel, limit, "pelvis travel \(travel) too large at runBlend \(runBlend)")
        }
    }

    // MARK: - Inverse kinematics

    func test_ik_preservesSegmentLengthsExactly() {
        let root = CGPoint(x: 60, y: 68)
        for angle in stride(from: 0.0, to: 2 * Double.pi, by: 0.15) {
            for reach in [5.0, 20.0, 38.0, 41.0, 80.0] {
                let target = CGPoint(x: root.x + CGFloat(cos(angle) * reach),
                                     y: root.y + CGFloat(sin(angle) * reach))
                let s = FigureGait.solveTwoBone(root: root, target: target, upper: 20.5, lower: 20.5, bendSign: 1)
                XCTAssertEqual(distance(root, s.joint), 20.5, accuracy: 0.05)
                XCTAssertEqual(distance(s.joint, s.end), 20.5, accuracy: 0.05)
            }
        }
    }

    func test_ik_clampsUnreachableTargetsInsteadOfStretching() {
        let root = CGPoint(x: 60, y: 60)
        let far = CGPoint(x: 60, y: 200)
        let s = FigureGait.solveTwoBone(root: root, target: far, upper: 20.5, lower: 20.5, bendSign: 1)
        XCTAssertLessThanOrEqual(distance(root, s.end), 41.0 + 0.01)
        XCTAssertEqual(distance(root, s.joint), 20.5, accuracy: 0.05)
    }

    func test_ik_bendDirectionNeverInverts() {
        let root = CGPoint(x: 60, y: 60)
        for dx in stride(from: -15.0, through: 15.0, by: 1.0) {
            let target = CGPoint(x: root.x + CGFloat(dx), y: root.y + 38)
            let s = FigureGait.solveTwoBone(root: root, target: target, upper: 20.5, lower: 20.5, bendSign: 1)
            // Knee must stay on the forward side of the hip→ankle line.
            let cross = (s.end.x - root.x) * (s.joint.y - root.y) - (s.end.y - root.y) * (s.joint.x - root.x)
            XCTAssertLessThan(cross, 0.001, "knee inverted at dx \(dx)")
        }
    }

    func test_ik_isFiniteForDegenerateTargets() {
        let root = CGPoint(x: 60, y: 60)
        let s = FigureGait.solveTwoBone(root: root, target: root, upper: 20.5, lower: 20.5, bendSign: 1)
        XCTAssertTrue(s.joint.x.isFinite && s.joint.y.isFinite)
        XCTAssertTrue(s.end.x.isFinite && s.end.y.isFinite)
    }

    // MARK: - runBlend

    func test_runBlend_requiresBothCadenceAndIntensity() {
        XCTAssertEqual(FigureGait.runBlend(cadence: 200, intensity: 0.2), 0, accuracy: 0.001,
                       "fast cadence at low effort must not trip running mechanics")
        XCTAssertEqual(FigureGait.runBlend(cadence: 90, intensity: 1), 0, accuracy: 0.001)
        XCTAssertGreaterThan(FigureGait.runBlend(cadence: 175, intensity: 1), 0.9)
    }

    func test_runBlend_isMonotonicAndBounded() {
        var previous = 0.0
        for cadence in stride(from: 80.0, through: 200.0, by: 2.0) {
            let v = FigureGait.runBlend(cadence: cadence, intensity: 1)
            XCTAssertGreaterThanOrEqual(v, previous - 0.0001)
            XCTAssertTrue(v >= 0 && v <= 1)
            previous = v
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
    }
}
