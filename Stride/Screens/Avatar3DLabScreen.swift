// Gate note: same temporary internal-testing switch as the Figure Lab —
// DEBUG covers local Xcode builds, STRIDE_INTERNAL_TESTING is set only for
// a deliberately dispatched internal TestFlight build. Never in a normal
// App Store Release.
#if DEBUG || STRIDE_INTERNAL_TESTING
import SwiftUI
import RealityKit
import Combine

// Phase 1.1B prototype — 3D Avatar Lab.
//
// Exists to answer one question: can an Avaturn character driven by a real
// Mixamo walk read as substantially more premium than the procedural Figure
// Rig V2? It is a measuring instrument, not a product screen, and it
// deliberately shares nothing with the production Home avatar. Figure Rig
// V2, FigureMotionEngine, MovementClassifier and StepProvider are all
// untouched by this file.
//
// The asset is a single animated USDZ built offline from the Avaturn GLB and
// the Mixamo FBX — see Tools/Avatar3D/convert_avatar.py. RealityKit cannot
// read GLB or FBX at runtime, so that conversion is not optional. The motion
// here is the real captured Mixamo walk, not procedural animation.
//
// RealityView is iOS 18+; this project deploys to iOS 17, so the scene is
// hosted in a non-AR ARView through UIViewRepresentable.

private enum AvatarCamera: String, CaseIterable, Identifiable {
    case front = "FRONT"
    case threeQuarter = "3/4"
    case side = "SIDE"

    var id: String { rawValue }

    /// Framing a ~1.7 m character standing at the origin, aimed at chest
    /// height so the walk reads without the head crowding the top edge.
    var position: SIMD3<Float> {
        switch self {
        case .front:        return [0.0, 1.05, 2.95]
        case .threeQuarter: return [2.05, 1.20, 2.15]
        case .side:         return [2.95, 1.05, 0.05]
        }
    }

    var target: SIMD3<Float> { [0, 0.95, 0] }
}

private enum PlaybackSpeed: Float, CaseIterable, Identifiable {
    case half = 0.5
    case normal = 1.0
    case quick = 1.25
    case fast = 1.5

    var id: Float { rawValue }
    var label: String { self == .normal ? "1.0×" : String(format: "%.2g×", rawValue) }
}

/// Owns the RealityKit scene. A class because the ARView, the loaded
/// character and the animation controller all outlive any single SwiftUI
/// view update, and because loading is asynchronous.
private final class AvatarScene: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published var state: LoadState = .loading

    let arView: ARView
    private var character: Entity?
    private var playback: AnimationPlaybackController?
    private var cancellable: AnyCancellable?
    private let camera = PerspectiveCamera()

    init() {
        arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(.black)
        // No AR passthrough, no plane detection, no scene understanding —
        // this is a lit turntable, nothing more.
        arView.renderOptions.insert(.disableMotionBlur)
        arView.renderOptions.insert(.disableDepthOfField)
        buildStage()
        load()
    }

    // MARK: - Stage

    private func buildStage() {
        let anchor = AnchorEntity(world: .zero)

        // Three-point lighting. Enough shaping for the body to read as
        // solid, deliberately short of anything theatrical.
        let key = DirectionalLight()
        key.light.intensity = 3200
        key.light.color = .white
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 4, depthBias: 1.5)
        key.look(at: [0, 0.9, 0], from: [-1.7, 2.7, 2.3], relativeTo: nil)

        let fill = DirectionalLight()
        fill.light.intensity = 900
        fill.light.color = .init(white: 0.85, alpha: 1)
        fill.shadow = nil
        fill.look(at: [0, 1.0, 0], from: [2.4, 1.5, 1.8], relativeTo: nil)

        // Separates the silhouette from a near-black background, which is
        // most of what stops a dark scene reading as flat.
        let rim = DirectionalLight()
        rim.light.intensity = 1400
        rim.light.color = .init(white: 0.95, alpha: 1)
        rim.shadow = nil
        rim.look(at: [0, 1.1, 0], from: [-0.8, 1.9, -2.6], relativeTo: nil)

        anchor.addChild(key)
        anchor.addChild(fill)
        anchor.addChild(rim)
        anchor.addChild(contactShadow())

        camera.camera.fieldOfViewInDegrees = 38
        anchor.addChild(camera)
        apply(camera: .threeQuarter)

        arView.scene.addAnchor(anchor)
    }

    /// A small dark disc directly under the feet. Not a cast shadow — just
    /// enough contact to stop the character reading as floating, and small
    /// enough that it never becomes scenery.
    private func contactShadow() -> ModelEntity {
        var material = UnlitMaterial(color: .black)
        material.blending = .transparent(opacity: 0.55)
        let disc = ModelEntity(
            mesh: .generatePlane(width: 0.62, depth: 0.42, cornerRadius: 0.21),
            materials: [material]
        )
        disc.position = [0, 0.001, 0]
        return disc
    }

    func apply(camera angle: AvatarCamera) {
        camera.look(at: angle.target, from: angle.position, relativeTo: nil)
    }

    // MARK: - Loading

    private func load() {
        cancellable = Entity.loadAsync(named: "AvatarWalk")
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.state = .failed(String(describing: error))
                }
            } receiveValue: { [weak self] entity in
                self?.attach(entity)
            }
    }

    private func attach(_ entity: Entity) {
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
        character = entity

        guard let clip = entity.availableAnimations.first else {
            state = .failed("USDZ contained no animation")
            return
        }
        playback = entity.playAnimation(clip.repeat(), transitionDuration: 0, startsPaused: false)
        state = .ready
    }

    // MARK: - Transport

    var isPlaying: Bool { playback?.isPlaying ?? false }

    func setPaused(_ paused: Bool) {
        guard let playback else { return }
        if paused { playback.pause() } else { playback.resume() }
    }

    func setSpeed(_ speed: Float) {
        playback?.speed = speed
    }
}

struct Avatar3DLabScreen: View {
    @StateObject private var scene = AvatarScene()
    @State private var camera: AvatarCamera = .threeQuarter
    @State private var speed: PlaybackSpeed = .normal
    @State private var paused = false

    var body: some View {
        ScreenScaffold(top: 24) {
            MonoLabel("3D AVATAR LAB — DEBUG ONLY", size: 10, color: .steel)
                .padding(.bottom, Space.block)

            stage
                .padding(.bottom, Space.block)

            transport
                .padding(.bottom, Space.unit)

            speedControl
                .padding(.bottom, Space.unit)

            cameraControl

            Spacer(minLength: 0)
        }
    }

    // MARK: - Stage

    @ViewBuilder private var stage: some View {
        ZStack {
            AvatarSceneView(scene: scene)
            switch scene.state {
            case .loading:
                MonoLabel("LOADING", size: 10, color: .dim)
            case .failed(let message):
                VStack(spacing: 6) {
                    MonoLabel("LOAD FAILED", size: 10, color: .danger)
                    Text(message)
                        .font(Type.archivo(11))
                        .foregroundStyle(Color.dim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.unit)
                }
            case .ready:
                EmptyView()
            }
        }
        .frame(height: 420)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    // MARK: - Controls

    private var transport: some View {
        Button {
            paused.toggle()
            scene.setPaused(paused)
        } label: {
            MonoLabel(paused ? "PLAY" : "PAUSE", size: 11, color: .ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.track)
        }
        .buttonStyle(.plain)
        .disabled(scene.state != .ready)
    }

    private var speedControl: some View {
        HStack(spacing: 8) {
            ForEach(PlaybackSpeed.allCases) { option in
                Button {
                    speed = option
                    scene.setSpeed(option.rawValue)
                } label: {
                    MonoLabel(option.label, size: 10, color: speed == option ? .steel : .dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.track)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cameraControl: some View {
        HStack(spacing: 8) {
            ForEach(AvatarCamera.allCases) { angle in
                Button {
                    camera = angle
                    scene.apply(camera: angle)
                } label: {
                    MonoLabel(angle.rawValue, size: 10, color: camera == angle ? .steel : .dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.track)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct AvatarSceneView: UIViewRepresentable {
    let scene: AvatarScene

    func makeUIView(context: Context) -> ARView { scene.arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}
#endif
