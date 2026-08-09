import SwiftUI

// The figure. Handoff §7 — viewBox 0 0 120 120, round caps and joins.
// Paths are transcribed verbatim from the SVG reference.

// Lives here (not Models) because the widget target shares this folder and
// needs it too.
enum UnlockTransform: String, Codable, CaseIterable, Hashable {
    case heavierLine, longShadow, steelOutline, motionTrail, inverted, thirtyDayMark
}

/// Live movement state, distinct from the day's cumulative step total.
/// Drives the Home avatar (LiveAvatar, below) — idle when nothing's
/// happening right now, walking at a normal cadence, active at a brisk
/// one. Purely a real-time read, never persisted. Lives here rather than
/// alongside StepProvider because the widget target compiles this file too.
enum ActivityState {
    case idle, walking, active
}

enum AvatarPose {
    case standing   // home, profile, reveal
    case raised     // milestone celebration
    case slumped    // Day 1 — Progression "before" side only
    case running    // intro slide 1 only

    /// Handoff §7: the slumped pose is drawn thinner than the rest.
    var strokeWidth: CGFloat { self == .slumped ? 1.6 : 2.2 }

    var head: (center: CGPoint, radius: CGFloat) {
        switch self {
        case .standing: return (CGPoint(x: 60, y: 22), 8)
        case .raised:   return (CGPoint(x: 60, y: 20), 8)
        case .slumped:  return (CGPoint(x: 60, y: 26), 7)
        case .running:  return (CGPoint(x: 72, y: 26), 7)
        }
    }
}

/// The body strokes for a pose, in the 120×120 reference box.
private struct FigureShape: Shape {
    let pose: AvatarPose

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch pose {
        case .standing:
            line(&p, [(60, 32), (60, 68)])
            line(&p, [(60, 44), (42, 58), (36, 54)])
            line(&p, [(60, 44), (78, 58), (84, 54)])
            line(&p, [(60, 68), (48, 90), (44, 102)])
            line(&p, [(60, 68), (72, 90), (76, 102)])

        case .raised:
            line(&p, [(60, 30), (60, 64)])
            line(&p, [(60, 40), (40, 30)])
            line(&p, [(60, 40), (80, 30)])
            line(&p, [(60, 64), (48, 88), (44, 100)])
            line(&p, [(60, 64), (72, 88), (76, 100)])

        case .slumped:
            p.move(to: CGPoint(x: 60, y: 34))
            p.addCurve(to: CGPoint(x: 60, y: 60),
                       control1: CGPoint(x: 58, y: 44),
                       control2: CGPoint(x: 58, y: 52))
            line(&p, [(60, 40), (46, 50)])
            line(&p, [(60, 40), (74, 50)])
            line(&p, [(60, 60), (52, 84), (50, 98)])
            line(&p, [(60, 60), (68, 84), (70, 98)])

        case .running:
            p.move(to: CGPoint(x: 70, y: 36))
            p.addCurve(to: CGPoint(x: 58, y: 62),
                       control1: CGPoint(x: 66, y: 46),
                       control2: CGPoint(x: 62, y: 54))
            line(&p, [(68, 42), (84, 50), (94, 44)])
            line(&p, [(66, 46), (52, 52), (44, 46)])
            line(&p, [(58, 62), (70, 74), (68, 92)])
            line(&p, [(58, 62), (46, 76), (32, 80)])
        }

        let head = pose.head
        p.addEllipse(in: CGRect(x: head.center.x - head.radius,
                                y: head.center.y - head.radius,
                                width: head.radius * 2,
                                height: head.radius * 2))

        // Scale the 120×120 reference box to whatever we were handed.
        let s = min(rect.width, rect.height) / 120
        return p.applying(CGAffineTransform(scaleX: s, y: s))
                .offsetBy(dx: (rect.width - 120 * s) / 2,
                          dy: (rect.height - 120 * s) / 2)
    }

    private func line(_ p: inout Path, _ pts: [(CGFloat, CGFloat)]) {
        guard let first = pts.first else { return }
        p.move(to: CGPoint(x: first.0, y: first.1))
        for pt in pts.dropFirst() { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
    }
}

/// Speed lines behind the running pose. Intro slide 1 only.
private struct SpeedLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (y, x0, x1) in [(38.0, 8.0, 34.0), (52.0, 4.0, 26.0), (66.0, 12.0, 30.0)] {
            p.move(to: CGPoint(x: x0, y: y))
            p.addLine(to: CGPoint(x: x1, y: y))
        }
        let s = min(rect.width, rect.height) / 120
        return p.applying(CGAffineTransform(scaleX: s, y: s))
                .offsetBy(dx: (rect.width - 120 * s) / 2,
                          dy: (rect.height - 120 * s) / 2)
    }
}

/// The figure, with any owned unlock transforms applied. Handoff §7.
struct AvatarView: View {
    var pose: AvatarPose = .standing
    var size: CGFloat = 200
    /// Transforms the user owns and has equipped.
    var transforms: Set<UnlockTransform> = []
    var speedLines: Bool = false
    /// Overrides the transform-derived color — for live, non-cosmetic states
    /// (e.g. dimmed while idle) that aren't part of the purchasable unlock
    /// system and shouldn't be confused with it.
    var strokeColorOverride: Color?

    private var strokeColor: Color {
        if let strokeColorOverride { return strokeColorOverride }
        if transforms.contains(.inverted) { return .void }
        if transforms.contains(.steelOutline) { return .steel }
        return .ink
    }

    private var strokeWidth: CGFloat {
        transforms.contains(.heavierLine) ? 3.2 : pose.strokeWidth
    }

    private var style: StrokeStyle {
        StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
    }

    var body: some View {
        ZStack {
            if transforms.contains(.inverted) {
                Circle().fill(Color.ink)
            }

            // Motion trail — duplicates behind, fading, offset horizontally.
            if transforms.contains(.motionTrail) {
                ForEach(1...3, id: \.self) { i in
                    FigureShape(pose: pose)
                        .stroke(strokeColor, style: style)
                        .opacity(0.30 / Double(i))
                        .offset(x: CGFloat(-7 * i))
                }
            }

            // Long shadow — one duplicate, translated and skewed, barely there.
            if transforms.contains(.longShadow) {
                FigureShape(pose: pose)
                    .stroke(strokeColor, style: style)
                    .opacity(0.15)
                    .transformEffect(CGAffineTransform(a: 1, b: 0, c: 0.45, d: 1, tx: 0, ty: 0))
                    .offset(x: 6, y: 8)
            }

            if speedLines {
                SpeedLines()
                    .stroke(Color.dimmer, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }

            FigureShape(pose: pose)
                .stroke(strokeColor, style: style)

            // Thirty-day mark — earned, not bought. A ring, nothing more.
            if transforms.contains(.thirtyDayMark) {
                Circle()
                    .stroke(Color.dimmer, lineWidth: 1)
                    .padding(2)
            }
        }
        .frame(width: size, height: size)
        .scaledToFit()
    }
}

/// Draws one instant of the procedural rig — the Phase 1.1A replacement for
/// switching between fixed `FigureShape` poses. Same stroke conventions
/// (round caps/joins) and the same 120×120 reference box, so it sits
/// visually consistent with the legacy static poses used elsewhere.
struct RigFigureShape: Shape {
    let joints: FigureJoints

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func segment(_ a: CGPoint, _ b: CGPoint) {
            p.move(to: a)
            p.addLine(to: b)
        }

        segment(joints.neck, joints.hipCenter)
        segment(joints.shoulderCenter, joints.leftShoulder)
        segment(joints.leftShoulder, joints.leftElbow)
        segment(joints.leftElbow, joints.leftHand)
        segment(joints.shoulderCenter, joints.rightShoulder)
        segment(joints.rightShoulder, joints.rightElbow)
        segment(joints.rightElbow, joints.rightHand)
        segment(joints.hipCenter, joints.leftHip)
        segment(joints.leftHip, joints.leftKnee)
        segment(joints.leftKnee, joints.leftFoot)
        segment(joints.hipCenter, joints.rightHip)
        segment(joints.rightHip, joints.rightKnee)
        segment(joints.rightKnee, joints.rightFoot)

        p.addEllipse(in: CGRect(x: joints.head.x - joints.headRadius,
                                y: joints.head.y - joints.headRadius,
                                width: joints.headRadius * 2,
                                height: joints.headRadius * 2))

        let s = min(rect.width, rect.height) / FigureRig.referenceSize
        return p.applying(CGAffineTransform(scaleX: s, y: s))
                .offsetBy(dx: (rect.width - FigureRig.referenceSize * s) / 2,
                          dy: (rect.height - FigureRig.referenceSize * s) / 2)
    }
}

/// Holds the mutable FigureMotionEngine as a reference so LiveAvatar can
/// advance it from inside a TimelineView tick without mutating `@State`
/// during a view update (which SwiftUI disallows) — the box itself is only
/// ever assigned once, into `@State`; everything that changes over time
/// lives inside it as plain var mutation on a class.
final class FigureMotionBox {
    var engine = FigureMotionEngine()
}

/// The Home avatar — Phase 1.1A: a continuous procedural rig instead of a
/// pose switch. There is no discrete "walking pose" vs "running pose"; the
/// figure is always the same rig, and CASUAL/WALKING/BRISK/RUNNING are just
/// where the gait parameters land as intensity/cadence rise, eased there by
/// FigureMotionEngine. Postural states (STILL/RISING/LOCOMOTION/SLOWING/
/// RECOVERING/RESTLESS/RESTING) decide what the rig is heading toward;
/// FigureRig only ever renders whatever the engine currently holds.
struct LiveAvatar: View {
    var activityState: ActivityState
    var intensity: Double = 0
    var movementTrend: MovementTrend = .steady
    var isInMovementSession: Bool = false
    var movementSessionDuration: TimeInterval? = nil
    var inactiveDuration: TimeInterval? = nil
    var smoothedCadence: Double = 0
    var size: CGFloat = 200
    var transforms: Set<UnlockTransform> = []
    /// Bump to fire the goal-breakthrough reaction: one quick forward
    /// step-and-settle. Compares against the previous value internally, so
    /// callers just pass a monotonically increasing counter (AppState's
    /// goalBreakthroughTick) and never need to reset it.
    var breakthroughTick: Int = 0

    /// Reduce Motion: no continuous gait cycling, no repeatForever bob, no
    /// aggressive springs. The rig still reflects the current postural
    /// state (a single static geometry per tick, no TimelineView clock) and
    /// a restrained opacity dip stands in for the breakthrough pulse —
    /// state stays legible without motion carrying it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var box = FigureMotionBox()
    @State private var breakthroughPulse = false

    private var inputs: FigureMotionInputs {
        FigureMotionInputs(activityState: activityState,
                           motionIntensity: intensity,
                           movementTrend: movementTrend,
                           isInMovementSession: isInMovementSession,
                           movementSessionDuration: movementSessionDuration,
                           inactiveDuration: inactiveDuration,
                           smoothedCadence: smoothedCadence)
    }

    private var stateDescription: String {
        switch box.engine.state {
        case .still, .resting:  return "standing still"
        case .rising:           return "starting to move"
        case .locomotion:       return intensity > 0.6 ? "moving briskly" : "walking"
        case .slowing:          return "slowing down"
        case .recovering:       return "settling"
        case .restless:         return "shifting weight"
        }
    }

    /// Idle/resting stays cheap; only visible locomotion asks for
    /// near-frame-rate updates. Read directly off the box (a plain class
    /// property read, not a state mutation) so it reflects whatever state
    /// the last tick landed in.
    private var refreshInterval: Double {
        switch box.engine.state {
        case .still, .resting:
            return MotionConfig.idleFrameInterval
        case .rising, .recovering, .restless:
            return MotionConfig.transitionFrameInterval
        case .locomotion, .slowing:
            return MotionConfig.activeFrameInterval
        }
    }

    private var strokeColor: Color {
        box.engine.state == .still || box.engine.state == .resting ? .dimmer : .ink
    }

    private var style: StrokeStyle {
        let lineWidth: CGFloat = transforms.contains(.heavierLine) ? 3.2 : 2.2
        return StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }

    var body: some View {
        Group {
            if reduceMotion {
                // One static frame per state change, no clock running.
                let g = box.engine.update(inputs)
                figure(for: FigureRig.joints(for: g))
            } else {
                TimelineView(.periodic(from: .now, by: refreshInterval)) { timeline in
                    let g = box.engine.update(inputs, now: timeline.date)
                    figure(for: FigureRig.joints(for: g))
                }
            }
        }
        .offset(x: (!reduceMotion && breakthroughPulse) ? MotionConfig.breakthroughOffsetX : 0)
        .scaleEffect((!reduceMotion && breakthroughPulse) ? MotionConfig.breakthroughScale : 1)
        .opacity(reduceMotion && breakthroughPulse ? 0.6 : 1)
        .animation(reduceMotion
                  ? .easeInOut(duration: MotionConfig.reducedMotionCrossfadeDuration)
                  : nil,
                  value: box.engine.state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Figure")
        .accessibilityValue(stateDescription)
        .onChange(of: breakthroughTick) { _, _ in
            let inAnim = reduceMotion
                ? Animation.easeInOut(duration: MotionConfig.reducedMotionCrossfadeDuration)
                : .spring(response: MotionConfig.breakthroughInResponse, dampingFraction: MotionConfig.breakthroughInDamping)
            let outAnim = reduceMotion
                ? Animation.easeInOut(duration: MotionConfig.reducedMotionCrossfadeDuration)
                : .spring(response: MotionConfig.breakthroughOutResponse, dampingFraction: MotionConfig.breakthroughOutDamping)
            withAnimation(inAnim) { breakthroughPulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + MotionConfig.breakthroughHoldDuration) {
                withAnimation(outAnim) { breakthroughPulse = false }
            }
        }
    }

    @ViewBuilder
    private func figure(for joints: FigureJoints) -> some View {
        ZStack {
            if transforms.contains(.inverted) {
                Circle().fill(Color.ink)
            }
            if transforms.contains(.motionTrail) {
                ForEach(1...3, id: \.self) { i in
                    RigFigureShape(joints: joints)
                        .stroke(effectiveStrokeColor, style: style)
                        .opacity(0.30 / Double(i))
                        .offset(x: CGFloat(-7 * i))
                }
            }
            if transforms.contains(.longShadow) {
                RigFigureShape(joints: joints)
                    .stroke(effectiveStrokeColor, style: style)
                    .opacity(0.15)
                    .transformEffect(CGAffineTransform(a: 1, b: 0, c: 0.45, d: 1, tx: 0, ty: 0))
                    .offset(x: 6, y: 8)
            }
            RigFigureShape(joints: joints)
                .stroke(effectiveStrokeColor, style: style)
            if transforms.contains(.thirtyDayMark) {
                Circle()
                    .stroke(Color.dimmer, lineWidth: 1)
                    .padding(2)
            }
        }
        .frame(width: size, height: size)
        .scaledToFit()
    }

    private var effectiveStrokeColor: Color {
        if transforms.contains(.inverted) { return .void }
        if transforms.contains(.steelOutline) { return .steel }
        return strokeColor
    }
}

#Preview {
    ZStack {
        Color.void.ignoresSafeArea()
        HStack(spacing: 0) {
            AvatarView(pose: .slumped, size: 120)
            AvatarView(pose: .standing, size: 120)
            AvatarView(pose: .raised, size: 120, transforms: [.steelOutline])
            AvatarView(pose: .running, size: 120, speedLines: true)
        }
    }
}

#Preview("Live states") {
    ZStack {
        Color.void.ignoresSafeArea()
        HStack(spacing: 0) {
            LiveAvatar(activityState: .idle, size: 120)
            LiveAvatar(activityState: .walking, size: 120)
            LiveAvatar(activityState: .active, size: 120)
        }
    }
}
