import AVFoundation
import Observation
import SwiftUI

@MainActor @Observable
final class CameraController {
    enum Status { case idle, unauthorized, unavailable, running }

    private(set) var status: Status = .idle
    private(set) var isTorchOn = false
    private(set) var isLocked = false
    var isPaperTrackEnabled = false
    var isHandOcclusionEnabled = false
    /// Frozen while `isLocked`.
    private(set) var trackedPaperQuad: PaperQuad?
    private(set) var handMaskImage: CGImage?
    /// Upright frame size; the canvasSize for `VisionTracker.warpStencil`.
    private(set) var frameSize: CGSize = .zero

    init() {}

    // STUB (Phase 0). Phase 4 adds CaptureEngine, the video output and tracking.
    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {}

    func start() async {}

    func stop() {}

    func setTorch(_ on: Bool) { isTorchOn = on }

    func setFocusExposureLocked(_ locked: Bool) { isLocked = locked }
}

struct CameraPreview: UIViewRepresentable {
    let controller: CameraController

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        controller.attachPreview(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
