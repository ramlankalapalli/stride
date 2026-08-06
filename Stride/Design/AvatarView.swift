import SwiftUI

// The figure. Handoff §7 — viewBox 0 0 120 120, round caps and joins.
// Paths are transcribed verbatim from the SVG reference.

// Lives here (not Models) because the widget target shares this folder and
// needs it too.
enum UnlockTransform: String, Codable, CaseIterable, Hashable {
    case heavierLine, longShadow, steelOutline, motionTrail, inverted, thirtyDayMark
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

    private var strokeColor: Color {
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
