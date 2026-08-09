// Gate note: DEBUG covers local Xcode debug builds; STRIDE_INTERNAL_TESTING
// is a temporary, manually-opted-in flag for a specific internal TestFlight
// build used to visually tune the Figure on-device (see Fastfile/build.yml).
// It is never set for a normal Release/App Store build.
#if DEBUG || STRIDE_INTERNAL_TESTING
import SwiftUI

// Development-only tool for visually tuning Phase 1.1A's Figure Motion
// Engine on-device. Not a product screen — reachable only via a #if DEBUG
// row on Profile (see ProfileScreens.swift) and a #if DEBUG Route case
// (see Route.swift / RootView.swift), so it never ships in a release build.
//
// Renders through the exact same FigureMotionEngine + FigureRig +
// RigFigureShape that LiveAvatar uses on Home — this is a set of manual
// inputs into the real engine, not a second animation system. The one
// exception is "Manual Gait" mode, which intentionally bypasses the
// postural state machine so raw gait parameters can be swept independently
// of what any real state would produce — still rendered by the same
// FigureRig, just fed parameters directly instead of through the engine.

private enum LabPreset: String, CaseIterable, Identifiable, Equatable {
    case rest = "RESTING", still = "STILL", restless = "RESTLESS"
    case rising = "RISING"
    case casual = "CASUAL", walk = "WALK", brisk = "BRISK", run = "RUN"
    case slowing = "SLOWING", recovering = "RECOVERING"

    var id: String { rawValue }

    var state: FigureMotionState {
        switch self {
        case .rest: return .resting
        case .still: return .still
        case .restless: return .restless
        case .rising: return .rising
        case .casual, .walk, .brisk, .run: return .locomotion
        case .slowing: return .slowing
        case .recovering: return .recovering
        }
    }

    /// The inputs kept feeding `update` while this preset is selected —
    /// this is what actually holds the figure in the intended state (or
    /// lets it evolve naturally, e.g. SLOWING will genuinely ease into
    /// RECOVERING then STILL on its own if you just watch it).
    var inputs: FigureMotionInputs {
        switch self {
        case .rest:
            return FigureMotionInputs(activityState: .idle, motionIntensity: 0, movementTrend: .steady,
                                      isInMovementSession: false, movementSessionDuration: nil,
                                      inactiveDuration: MotionConfig.restingInactivityThreshold + 60, smoothedCadence: 0)
        case .still:
            return .idle
        case .restless:
            return FigureMotionInputs(activityState: .idle, motionIntensity: 0, movementTrend: .steady,
                                      isInMovementSession: false, movementSessionDuration: nil,
                                      inactiveDuration: MotionConfig.restlessInactivityThreshold + 30, smoothedCadence: 0)
        case .rising:
            return FigureMotionInputs(activityState: .walking, motionIntensity: 0.3, movementTrend: .rising,
                                      isInMovementSession: true, movementSessionDuration: 0, inactiveDuration: nil, smoothedCadence: 90)
        case .casual:
            return FigureMotionInputs(activityState: .walking, motionIntensity: 0.15, movementTrend: .steady,
                                      isInMovementSession: true, movementSessionDuration: 30, inactiveDuration: nil, smoothedCadence: 85)
        case .walk:
            return FigureMotionInputs(activityState: .walking, motionIntensity: 0.4, movementTrend: .steady,
                                      isInMovementSession: true, movementSessionDuration: 60, inactiveDuration: nil, smoothedCadence: 112)
        case .brisk:
            return FigureMotionInputs(activityState: .active, motionIntensity: 0.7, movementTrend: .steady,
                                      isInMovementSession: true, movementSessionDuration: 90, inactiveDuration: nil, smoothedCadence: 138)
        case .run:
            return FigureMotionInputs(activityState: .active, motionIntensity: 0.97, movementTrend: .steady,
                                      isInMovementSession: true, movementSessionDuration: 120, inactiveDuration: nil, smoothedCadence: 168)
        case .slowing, .recovering:
            return FigureMotionInputs(activityState: .idle, motionIntensity: 0, movementTrend: .falling,
                                      isInMovementSession: false, movementSessionDuration: nil, inactiveDuration: 0, smoothedCadence: 0)
        }
    }
}

private enum LabSequence: String, CaseIterable, Identifiable {
    case restToWalk = "RESTING → RISING → WALK"
    case fullRamp = "STILL → RISING → WALK → BRISK → RUN"
    case runToStill = "RUN → SLOWING → RECOVERING → STILL"
    case restlessToWalk = "RESTLESS → RISING → WALK"

    var id: String { rawValue }

    var steps: [LabPreset] {
        switch self {
        case .restToWalk:      return [.rest, .rising, .walk]
        case .fullRamp:        return [.still, .rising, .walk, .brisk, .run]
        case .runToStill:      return [.run, .slowing, .recovering, .still]
        case .restlessToWalk:  return [.restless, .rising, .walk]
        }
    }
}

/// Tracks a synthetic playback clock so the SPEED control can slow down
/// both the engine-driven preview and the manual phase sweep without
/// touching real wall-clock time anywhere else in the app. A plain class in
/// @State for the same reason FigureMotionBox is one — mutated from inside
/// a TimelineView tick, not through SwiftUI's @State setter.
private final class LabClock {
    var lastRealDate: Date?
    var syntheticDate = Date()
    var manualPhase: Double = 0
}

/// Snapshot of the frame currently on screen, for the debug readout.
/// A class for the same reason LabClock is one — written from inside a
/// TimelineView tick.
private final class InspectedFrame {
    var gait = FigureGaitParameters.neutral
    var joints = FigureRig.joints(for: .neutral)
    var duty: Double = 0
}

/// Ground plane and per-foot contact marks. Figure Lab only — this is never
/// constructed anywhere in the production view hierarchy.
private struct LabGroundOverlay: View {
    let joints: FigureJoints
    let showJoints: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Path { p in
                    let y = groundLineY(in: geo.size)
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(Color.steel.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // Filled = planted, hollow = swinging.
                contactMark(at: place(joints.leftAnkle, in: geo.size), planted: joints.leftPlanted)
                contactMark(at: place(joints.rightAnkle, in: geo.size), planted: joints.rightPlanted)

                if showJoints {
                    ForEach(Array(jointPoints.enumerated()), id: \.offset) { _, point in
                        Circle()
                            .fill(Color.steel.opacity(0.7))
                            .frame(width: 3, height: 3)
                            .position(place(point, in: geo.size))
                    }
                }
            }
        }
    }

    /// Same scale-and-centre transform RigFigureShape applies, so the
    /// overlay lines up with the drawn Figure exactly.
    private func place(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let scale = min(size.width, size.height) / FigureRig.referenceSize
        return CGPoint(x: (size.width - FigureRig.referenceSize * scale) / 2 + p.x * scale,
                       y: (size.height - FigureRig.referenceSize * scale) / 2 + p.y * scale)
    }

    private func groundLineY(in size: CGSize) -> CGFloat {
        place(CGPoint(x: 0, y: MotionConfig.groundY), in: size).y
    }

    private var jointPoints: [CGPoint] {
        [joints.leftShoulder, joints.rightShoulder, joints.leftElbow, joints.rightElbow,
         joints.leftHand, joints.rightHand, joints.hipCenter, joints.leftHip, joints.rightHip,
         joints.leftKnee, joints.rightKnee, joints.leftAnkle, joints.rightAnkle, joints.neck]
    }

    @ViewBuilder
    private func contactMark(at point: CGPoint, planted: Bool) -> some View {
        Circle()
            .strokeBorder(Color.steel, lineWidth: 1)
            .background(Circle().fill(planted ? Color.steel : Color.clear))
            .frame(width: 6, height: 6)
            .position(point)
    }
}

struct FigureLabScreen: View {
    @State private var box = FigureMotionBox()
    @State private var clock = LabClock()
    @State private var currentPreset: LabPreset = .still
    @State private var currentInputs: FigureMotionInputs = .idle
    @State private var playbackSpeed: Double = 1.0
    @State private var manualMode = false
    @State private var manualGait = FigureGaitParameters.neutral
    @State private var sequenceTask: Task<Void, Never>?
    @State private var showGround = true
    @State private var showJoints = false
    /// Whatever was last rendered, kept so the readout below the preview
    /// reports the exact frame on screen rather than re-deriving it.
    @State private var inspected = InspectedFrame()

    private var refreshInterval: Double {
        switch box.engine.state {
        case .still, .resting: return MotionConfig.idleFrameInterval
        case .rising, .recovering, .restless: return MotionConfig.transitionFrameInterval
        case .locomotion, .slowing: return MotionConfig.activeFrameInterval
        }
    }

    var body: some View {
        ScreenScaffold(top: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MonoLabel("FIGURE LAB — DEBUG ONLY", size: 10, color: .steel)
                        .padding(.bottom, Space.block)

                    figurePreview
                        .padding(.bottom, Space.block)

                    debugReadout
                        .padding(.bottom, Space.block)

                    playbackSpeedControl
                        .padding(.bottom, Space.block)

                    Toggle("Ground line", isOn: $showGround)
                        .tint(.steel)
                    Toggle("Joint markers", isOn: $showJoints)
                        .tint(.steel)
                    Toggle("Manual gait override", isOn: $manualMode)
                        .tint(.steel)
                        .padding(.bottom, Space.small)

                    if manualMode {
                        manualControls
                    } else {
                        presetGrid
                            .padding(.bottom, Space.block)
                        sequenceButtons
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        .onDisappear { sequenceTask?.cancel() }
    }

    // MARK: - Preview

    @ViewBuilder private var figurePreview: some View {
        ZStack {
            if manualMode {
                TimelineView(.periodic(from: .now, by: MotionConfig.activeFrameInterval)) { timeline in
                    frameStack(joints: manualJoints(at: timeline.date))
                }
            } else {
                TimelineView(.periodic(from: .now, by: refreshInterval)) { timeline in
                    frameStack(joints: engineJoints(at: timeline.date))
                }
            }
        }
        .frame(width: 220, height: 220)
        .frame(maxWidth: .infinity)
        .background(Color.track)
    }

    private func frameStack(joints: FigureJoints) -> some View {
        ZStack {
            if showGround {
                LabGroundOverlay(joints: joints, showJoints: showJoints)
            }
            RigFigureShape(joints: joints)
                .stroke(Color.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
    }

    private func manualJoints(at now: Date) -> FigureJoints {
        let dt = clock.lastRealDate.map { now.timeIntervalSince($0) } ?? 0
        clock.lastRealDate = now
        let hz = manualGait.energy > 0.01 ? max(0.1, manualGait.cadence / 60 / 2) : 0
        var phase = clock.manualPhase + hz * dt * playbackSpeed
        phase = phase.truncatingRemainder(dividingBy: 1)
        clock.manualPhase = phase
        var rendered = manualGait
        rendered.phase = phase
        return record(rendered)
    }

    private func engineJoints(at now: Date) -> FigureJoints {
        let dt = clock.lastRealDate.map { now.timeIntervalSince($0) } ?? 0
        clock.lastRealDate = now
        clock.syntheticDate = clock.syntheticDate.addingTimeInterval(dt * playbackSpeed)
        return record(box.engine.update(currentInputs, now: clock.syntheticDate))
    }

    private func record(_ gait: FigureGaitParameters) -> FigureJoints {
        let joints = FigureRig.joints(for: gait)
        inspected.gait = gait
        inspected.joints = joints
        inspected.duty = FigureGait.dutyFactor(runBlend: gait.runBlend)
        return joints
    }

    // MARK: - Debug readout

    /// On its own slow clock: the preview's TimelineView only re-renders
    /// its own content, so without this the numbers below it would freeze
    /// at whatever they were when the screen was last laid out.
    private var debugReadout: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 10)) { _ in
            readoutBody
        }
    }

    @ViewBuilder private var readoutBody: some View {
        let g = inspected.gait
        let j = inspected.joints
        VStack(alignment: .leading, spacing: 4) {
            row("state", manualMode ? "manual" : "\(box.engine.state)")
            row("phase", String(format: "%.2f", g.phase))
            row("intensity", String(format: "%.2f", g.intensity))
            row("cadence", String(format: "%.0f", g.cadence))
            row("stride", String(format: "%.1f", g.strideLength))
            row("lean", String(format: "%.1f°", g.forwardLean))
            row("armSwing", String(format: "%.1f°", g.armSwing))
            row("bob", String(format: "%.2f", g.verticalBob))
            row("energy", String(format: "%.2f", g.energy))
            row("runBlend", String(format: "%.2f", g.runBlend))
            row("duty", String(format: "%.2f%@", inspected.duty, inspected.duty < 0.5 ? "  (flight)" : ""))
            row("contact", contactLabel(j))
            row("pelvis Y", String(format: "%.1f", j.hipCenter.y))
            row("L ankle", String(format: "%.1f, %.1f", j.leftAnkle.x, j.leftAnkle.y))
            row("R ankle", String(format: "%.1f, %.1f", j.rightAnkle.x, j.rightAnkle.y))
            row("L knee", String(format: "%.1f, %.1f", j.leftKnee.x, j.leftKnee.y))
            row("R knee", String(format: "%.1f, %.1f", j.rightKnee.x, j.rightKnee.y))
            row("weightShift", String(format: "%.2f", g.weightShift))
        }
    }

    private func contactLabel(_ j: FigureJoints) -> String {
        switch (j.leftPlanted, j.rightPlanted) {
        case (true, true):   return "L+R  double"
        case (true, false):  return "L    stance"
        case (false, true):  return "R    stance"
        case (false, false): return "—    flight"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            MonoLabel(label, size: 10, color: .dim)
            Spacer()
            MonoLabel(value, size: 10, color: .ink)
        }
    }

    // MARK: - Playback speed

    private var playbackSpeedControl: some View {
        HStack {
            MonoLabel("SPEED", size: 10, color: .dim)
            Spacer()
            Picker("Speed", selection: $playbackSpeed) {
                Text("0.25×").tag(0.25)
                Text("0.5×").tag(0.5)
                Text("1×").tag(1.0)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
    }

    // MARK: - Preset grid

    private var presetGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(LabPreset.allCases) { preset in
                Button {
                    apply(preset)
                } label: {
                    MonoLabel(preset.rawValue, size: 10, color: currentPreset == preset ? .steel : .dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.track)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Sequences

    private var sequenceButtons: some View {
        VStack(spacing: 8) {
            ForEach(LabSequence.allCases) { sequence in
                Button {
                    playSequence(sequence)
                } label: {
                    MonoLabel(sequence.rawValue, size: 10, color: .ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color.track)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func playSequence(_ sequence: LabSequence) {
        sequenceTask?.cancel()
        sequenceTask = Task { @MainActor in
            for step in sequence.steps {
                apply(step)
                let holdSeconds = 1.6 / playbackSpeed
                try? await Task.sleep(nanoseconds: UInt64(holdSeconds * 1_000_000_000))
                if Task.isCancelled { return }
            }
        }
    }

    private func apply(_ preset: LabPreset) {
        currentPreset = preset
        currentInputs = preset.inputs
        box.engine.debugForceState(preset.state)
    }

    // MARK: - Manual gait controls

    private var manualControls: some View {
        VStack(spacing: 14) {
            slider("intensity", $manualGait.intensity, 0...1)
            slider("cadence", Binding(get: { manualGait.cadence }, set: { manualGait.cadence = $0 }), 0...200)
            slider("stride", Binding(get: { Double(manualGait.strideLength) }, set: { manualGait.strideLength = CGFloat($0) }), 0...30)
            slider("lean", $manualGait.forwardLean, 0...12)
            slider("armSwing°", Binding(get: { Double(manualGait.armSwing) }, set: { manualGait.armSwing = CGFloat($0) }), 0...35)
            slider("bob", Binding(get: { Double(manualGait.verticalBob) }, set: { manualGait.verticalBob = CGFloat($0) }), 0...4)
            slider("energy", $manualGait.energy, 0...1)
            slider("runBlend", $manualGait.runBlend, 0...1)
            slider("weightShift", Binding(get: { Double(manualGait.weightShift) }, set: { manualGait.weightShift = CGFloat($0) }), -4...4)
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                MonoLabel(label, size: 10, color: .dim)
                Spacer()
                MonoLabel(String(format: "%.1f", value.wrappedValue), size: 10, color: .ink)
            }
            Slider(value: value, in: range)
                .tint(.steel)
        }
    }
}

#Preview {
    ZStack {
        Color.void.ignoresSafeArea()
        FigureLabScreen()
    }
}
#endif
