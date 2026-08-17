// Gate note: same temporary internal-testing switch as the Figure Lab —
// DEBUG covers local Xcode builds, STRIDE_INTERNAL_TESTING is set only for
// a deliberately dispatched internal TestFlight build. Never in a normal
// App Store Release.
#if DEBUG || STRIDE_INTERNAL_TESTING
import SwiftUI
import RealityKit
import Combine
import CoreGraphics
import UIKit

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

    /// Pulled back and shot long (see `fieldOfView`). The wider, closer
    /// setup read like a model viewer: perspective divergence made the
    /// nearer leg balloon and the figure sat in the frame like a specimen.
    /// A longer lens from further away compresses the body the way product
    /// and athletic photography does, and framing the figure large makes it
    /// the subject rather than an exhibit.
    var position: SIMD3<Float> {
        switch self {
        case .front:        return [0.00, 0.88, 3.85]
        case .threeQuarter: return [2.58, 0.98, 2.85]
        case .side:         return [3.85, 0.88, 0.02]
        }
    }

    /// Aimed at the hips rather than the chest, with the camera sitting a
    /// little below it — the eye reads a slight upward angle as presence.
    var target: SIMD3<Float> { [0, 0.98, 0] }
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

        // The default non-AR environment lights the scene fairly evenly,
        // which on a black background flattens the body into a silhouette.
        // Pulling the ambient down lets the three lights below do the
        // shaping, so form reads instead of outline.
        arView.environment.lighting.intensityExponent = -0.6

        // Key: high and to camera-left. Carries the face and the front of
        // the torso, and is the only light casting a shadow.
        let key = DirectionalLight()
        key.light.intensity = 5200
        key.light.color = .init(white: 1.0, alpha: 1)
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 6, depthBias: 1.2)
        key.look(at: [0, 1.0, 0], from: [-1.9, 3.0, 2.6], relativeTo: nil)

        // Fill: opposite the key, deliberately weak. Enough to keep the
        // shadow side from going to pure black, not enough to flatten it.
        let fill = DirectionalLight()
        fill.light.intensity = 850
        fill.light.color = .init(white: 0.82, alpha: 1)
        fill.shadow = nil
        fill.look(at: [0, 1.05, 0], from: [2.7, 1.4, 1.9], relativeTo: nil)

        // Two rims from behind, one per side. This is what actually
        // separates a dark figure from a black background — a single back
        // light leaves one edge buried, and the silhouette breaks up.
        let rimLeft = DirectionalLight()
        rimLeft.light.intensity = 3000
        rimLeft.light.color = .init(white: 0.97, alpha: 1)
        rimLeft.shadow = nil
        rimLeft.look(at: [0, 1.15, 0], from: [-2.3, 2.0, -2.4], relativeTo: nil)

        let rimRight = DirectionalLight()
        rimRight.light.intensity = 2100
        rimRight.light.color = .init(white: 0.94, alpha: 1)
        rimRight.shadow = nil
        rimRight.look(at: [0, 1.15, 0], from: [2.5, 1.9, -2.2], relativeTo: nil)

        anchor.addChild(key)
        anchor.addChild(fill)
        anchor.addChild(rimLeft)
        anchor.addChild(rimRight)
        anchor.addChild(contactShadow())

        camera.camera.fieldOfViewInDegrees = 30
        anchor.addChild(camera)
        apply(camera: .threeQuarter)

        arView.scene.addAnchor(anchor)
    }

    /// Soft contact shadow under the feet.
    ///
    /// The first version was a hard-edged rounded rectangle, which reads as
    /// a sticker on the floor rather than as shadow — and because an
    /// in-place walk slides its planted foot backwards, a crisp static
    /// shape is exactly the reference that makes the sliding obvious. A
    /// radial falloff has no edge to slide against, so it grounds the
    /// figure without advertising the treadmill.
    ///
    /// Sized to the stride footprint rather than to one foot, since both
    /// feet travel through it over a cycle.
    private func contactShadow() -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: 1.05, depth: 0.78)
        var material = UnlitMaterial(color: .black)
        material.blending = .transparent(opacity: 0.85)

        if let texture = Self.radialFalloffTexture() {
            material.color = .init(tint: .white, texture: .init(texture))
        }

        let shadow = ModelEntity(mesh: mesh, materials: [material])
        // Just above the floor so it never z-fights with geometry that
        // dips slightly below during toe-off.
        shadow.position = [0, 0.002, 0]
        return shadow
    }

    /// Black disc fading to fully transparent at the rim, drawn once at
    /// startup. Premultiplied so the edge fades out rather than towards
    /// grey.
    private static func radialFalloffTexture() -> TextureResource? {
        let size = 256
        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 0, count: size * bytesPerRow)
        let centre = Float(size - 1) / 2

        for y in 0..<size {
            for x in 0..<size {
                let dx = (Float(x) - centre) / centre
                let dy = (Float(y) - centre) / centre
                let distance = min(1, sqrt(dx * dx + dy * dy))
                // Squared falloff, then eased — keeps a denser core under
                // the feet with a long soft tail.
                let falloff = powf(1 - distance, 2.2)
                let alpha = UInt8(max(0, min(255, falloff * 255)))
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = 0      // premultiplied black
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = alpha
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: size, height: size,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent)
        else { return nil }

        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
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
