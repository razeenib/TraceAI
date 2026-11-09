import SwiftUI

struct TracingView: View {
    let stencil: StencilSet

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var camera = CameraController()

    @State private var opacity: Double = 0.6
    @State private var step = 3
    @State private var snapped: UIImage?
    @State private var pausedInBackground = false

    // Committed manual transform.
    @State private var scale: CGFloat = 1
    @State private var angle: Angle = .zero
    @State private var offset: CGSize = .zero
    // Live pinch/rotate values; nil while that gesture is inactive (auto-reset on cancel).
    @GestureState private var liveScale: CGFloat? = nil
    @GestureState private var liveAngle: Angle? = nil
    @GestureState private var isDragging = false
    // Drag offset, re-baselined while a pinch or rotate is active so lifting a finger doesn't jump.
    @State private var dragBase: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    private struct SnapKey: Equatable { let quad: PaperQuad?; let layer: Int }

    private var isPro: Bool { PaywallManager.shared.isPro }

    private var currentImage: UIImage {
        guard isPro, stencil.layers.indices.contains(step - 1) else { return stencil.full }
        return stencil.layers[step - 1]
    }

    private var snapQuad: PaperQuad? { camera.isPaperTrackEnabled ? camera.trackedPaperQuad : nil }

    var body: some View {
        ZStack {
            switch camera.status {
            case .unauthorized: unauthorizedView
            case .unavailable:
                ContentUnavailableView("Camera Unavailable", systemImage: "video.slash",
                                       description: Text("TraceAI couldn't start the back camera on this device."))
            case .idle, .running: tracingLayers
            }

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if camera.status == .idle || camera.status == .running {
                    TracingDock(camera: camera, opacity: $opacity, step: $step)
                        .padding(.bottom, 8)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task(id: SnapKey(quad: snapQuad, layer: isPro ? step : 0)) { await updateSnappedStencil() }
        .onChange(of: isDragging) { _, dragging in if !dragging { commitDrag() } }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .task { await camera.start() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; camera.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { camera.stop(); pausedInBackground = true }
            if phase == .active && pausedInBackground {
                pausedInBackground = false
                Task { await camera.start() }
            }
        }
    }

    // Bottom to top: camera, stencil, hand mask (so lines sit under fingers and pencil).
    private var tracingLayers: some View {
        ZStack {
            CameraPreview(controller: camera)
                .ignoresSafeArea()
            Group {
                if snapQuad != nil {
                    if let snapped { cameraSpace(Image(uiImage: snapped)) }
                } else {
                    manualStencil
                }
            }
            .opacity(opacity)
            if camera.isHandOcclusionEnabled, let mask = camera.handMaskImage {
                cameraSpace(Image(decorative: mask, scale: 1))
            }
        }
    }

    /// Full-screen camera-space image, clipped so a 9:16 frame can't widen the ZStack.
    private func cameraSpace(_ image: Image) -> some View {
        GeometryReader { geo in
            image.resizable().scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height).clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var manualStencil: some View {
        Image(uiImage: currentImage)
            .resizable()
            .scaledToFit()
            .padding(24)
            .scaleEffect(scale * (liveScale ?? 1))
            .rotationEffect(angle + (liveAngle ?? .zero))
            .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(manipulation, including: camera.isLocked ? GestureMask.none : .all)
            .allowsHitTesting(!camera.isLocked)
    }

    private var manipulation: some Gesture {
        let magnify = MagnifyGesture()
            .updating($liveScale) { value, state, _ in state = value.magnification }
            .onEnded { value in scale = min(max(scale * value.magnification, 0.2), 5) }
        let rotate = RotateGesture()
            .updating($liveAngle) { value, state, _ in state = value.rotation }
            .onEnded { value in angle += value.rotation }
        let drag = DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                let t = value.translation
                if liveScale != nil || liveAngle != nil {
                    // Pinch/rotate active: hold the offset and keep the baseline in step with the fingers.
                    dragBase = CGSize(width: t.width - dragOffset.width, height: t.height - dragOffset.height)
                } else {
                    dragOffset = CGSize(width: t.width - dragBase.width, height: t.height - dragBase.height)
                }
            }
            .onEnded { _ in commitDrag() }
        return magnify.simultaneously(with: rotate).simultaneously(with: drag)
    }

    /// Idempotent, so it is safe from both `onEnded` and the cancel path.
    private func commitDrag() {
        offset = CGSize(width: offset.width + dragOffset.width, height: offset.height + dragOffset.height)
        dragOffset = .zero; dragBase = .zero
    }

    private func resetAlignment() {
        withAnimation(.snappy) {
            scale = 1; angle = .zero; offset = .zero; dragOffset = .zero; dragBase = .zero
        }
    }

    private func updateSnappedStencil() async {
        guard let quad = snapQuad else { snapped = nil; return }
        let image = currentImage
        let half = CGSize(width: camera.frameSize.width * 0.5, height: camera.frameSize.height * 0.5)
        guard half.width >= 1, half.height >= 1 else { return }
        let warped = await Task.detached(priority: .userInitiated) {
            VisionTracker.warpStencil(image, to: quad, canvasSize: half)
        }.value
        guard !Task.isCancelled else { return }
        snapped = warped
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close")
            Spacer()
            if !camera.isLocked && snapQuad == nil {
                Button(action: resetAlignment) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var unauthorizedView: some View {
        ContentUnavailableView {
            Label("Camera Access Needed", systemImage: "camera.fill")
        } description: {
            Text("TraceAI shows your paper through the camera so you can trace the stencil. Video never leaves your iPhone.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
