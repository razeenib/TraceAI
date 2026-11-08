import AVFoundation
import Observation
import os
import SwiftUI

@MainActor @Observable
final class CameraController {
    enum Status { case idle, unauthorized, unavailable, running }

    private(set) var status: Status = .idle
    private(set) var isTorchOn = false
    private(set) var isLocked = false
    var isPaperTrackEnabled = false {
        didSet {
            guard isPaperTrackEnabled != oldValue else { return }
            if !isPaperTrackEnabled { trackedPaperQuad = nil }
            engine.setPaperTracking(isPaperTrackEnabled)
        }
    }
    var isHandOcclusionEnabled = false {
        didSet {
            guard isHandOcclusionEnabled != oldValue else { return }
            if !isHandOcclusionEnabled { handMaskImage = nil }
            engine.setHandOcclusion(isHandOcclusionEnabled)
        }
    }
    /// Frozen while `isLocked`.
    private(set) var trackedPaperQuad: PaperQuad?
    private(set) var handMaskImage: CGImage?
    /// Upright frame size; the canvasSize for `VisionTracker.warpStencil`.
    private(set) var frameSize: CGSize = .zero

    @ObservationIgnored private let engine = CaptureEngine()
    @ObservationIgnored private var previewLayer: AVCaptureVideoPreviewLayer?
    /// Bumped by `start()` and `stop()` so a stop during a pending start wins.
    @ObservationIgnored private var generation = 0

    init() {
        engine.setFrameHandler { [weak self] frame in
            guard let self else { return }
            Task { @MainActor in self.apply(frame) }
        }
    }

    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        layer.session = engine.session
        layer.videoGravity = .resizeAspectFill
        rotatePreview()
    }

    func start() async {
        guard status != .running else { return }
        generation += 1
        let current = generation
        guard await Self.requestAccess() else { status = .unauthorized; return }
        guard current == generation else { return }
        guard let size = await engine.configure() else { status = .unavailable; return }
        guard current == generation else { return }
        frameSize = size
        rotatePreview()
        await engine.startRunning()
        guard current == generation else { return }
        status = .running
    }

    func stop() {
        generation += 1
        engine.stop()
        if status == .running { status = .idle }
        isTorchOn = false
        trackedPaperQuad = nil
        handMaskImage = nil
    }

    func setTorch(_ on: Bool) {
        Task { isTorchOn = await engine.setTorch(on) }
    }

    func setFocusExposureLocked(_ locked: Bool) {
        isLocked = locked
        engine.setLocked(locked)
    }

    private func apply(_ frame: CaptureEngine.FrameResult) {
        guard status == .running else { return }
        if frame.trackedPaper, isPaperTrackEnabled, !isLocked { trackedPaperQuad = frame.output.quad }
        if frame.maskedHands, isHandOcclusionEnabled { handMaskImage = frame.output.handMask }
        let size = frame.output.frameSize
        if size != .zero, size != frameSize { frameSize = size }
    }

    private func rotatePreview() {
        guard let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(90) else { return }
        connection.videoRotationAngle = 90
    }

    private static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

/// Owns the capture session, the device and the video delegate. Session and device work
/// runs on `sessionQueue`; frames and the tracker run on `videoQueue`.
private final class CaptureEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct FrameResult: Sendable {
        let output: TrackerOutput
        let trackedPaper: Bool
        let maskedHands: Bool
    }

    private struct State: Sendable {
        var paper = false
        var hands = false
        var locked = false
        var onFrame: (@Sendable (FrameResult) -> Void)?
    }

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "TraceAI.camera.session")
    private let videoQueue = DispatchQueue(label: "TraceAI.camera.video", qos: .userInitiated)
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let tracker = VisionTracker()
    private var device: AVCaptureDevice?           // sessionQueue only
    private var configuredSize: CGSize?            // sessionQueue only
    private var lastFrameTime: CFTimeInterval = 0  // videoQueue only

    func setFrameHandler(_ handler: @escaping @Sendable (FrameResult) -> Void) {
        state.withLock { $0.onFrame = handler }
    }

    func setPaperTracking(_ on: Bool) {
        state.withLock { $0.paper = on }
        if on { videoQueue.async { [tracker] in tracker.reset() } }
    }

    func setHandOcclusion(_ on: Bool) {
        state.withLock { $0.hands = on }
    }

    func setLocked(_ locked: Bool) {
        state.withLock { $0.locked = locked }
        sessionQueue.async { [self] in applyFocusExposureLock(locked) }
    }

    /// Returns the upright frame size, or nil when there is no usable back camera.
    func configure() async -> CGSize? {
        await onSessionQueue { $0.configureOnQueue() }
    }

    func startRunning() async {
        await onSessionQueue { engine in
            if !engine.session.isRunning { engine.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            _ = applyTorch(false)
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Returns the resulting torch state.
    func setTorch(_ on: Bool) async -> Bool {
        await onSessionQueue { $0.applyTorch(on) }
    }

    // MARK: Video delegate (videoQueue)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let current = state.withLock { $0 }
        let trackPaper = current.paper && !current.locked
        guard trackPaper || current.hands else { return }

        let now = CACurrentMediaTime()
        let hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        guard now - lastFrameTime >= (hot ? 1.0 / 10 : 1.0 / 15) else { return }
        lastFrameTime = now

        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let result = tracker.process(buffer, trackPaper: trackPaper, maskHands: current.hands)
        current.onFrame?(FrameResult(output: result, trackedPaper: trackPaper, maskedHands: current.hands))
    }

    // MARK: Session queue

    private func onSessionQueue<T: Sendable>(_ work: @escaping @Sendable (CaptureEngine) -> T) async -> T {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in continuation.resume(returning: work(self)) }
        }
    }

    private func configureOnQueue() -> CGSize? {
        if let configuredSize { return configuredSize }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return nil }

        session.beginConfiguration()
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        guard session.canAddInput(input), session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            return nil
        }
        session.addInput(input)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        session.addOutput(videoOutput)
        if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        session.commitConfiguration()

        device = camera
        // Buffers are rotated 90°, so the upright frame swaps the sensor's width and height.
        let dims = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
        let size = CGSize(width: CGFloat(dims.height), height: CGFloat(dims.width))
        configuredSize = size
        return size
    }

    private func applyTorch(_ on: Bool) -> Bool {
        guard let device, device.hasTorch else { return false }
        let mode: AVCaptureDevice.TorchMode = on ? .on : .off
        guard device.isTorchModeSupported(mode), (try? device.lockForConfiguration()) != nil else {
            return device.torchMode == .on
        }
        device.torchMode = mode
        device.unlockForConfiguration()
        return on
    }

    private func applyFocusExposureLock(_ locked: Bool) {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if locked {
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            if !device.isAdjustingWhiteBalance && device.isWhiteBalanceModeSupported(.locked) {
                device.whiteBalanceMode = .locked
            }
        } else {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        }
    }
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
