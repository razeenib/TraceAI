import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import os
import UIKit
import Vision

/// Paper corners, normalized 0–1 with a top-left origin, in the upright portrait camera frame.
struct PaperQuad: Sendable, Equatable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint
}

struct TrackerOutput: @unchecked Sendable {
    let quad: PaperQuad?
    /// Hand pixels on a transparent background; nil if no hand was found.
    let handMask: CGImage?
    /// Upright frame size in pixels.
    let frameSize: CGSize
}

final class VisionTracker: @unchecked Sendable {
    /// One shared context for the per-frame mask and the stencil warp (CIContext is thread-safe).
    nonisolated(unsafe) private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let maskLongSide: CGFloat = 960
    private static let emptyMaskThreshold: CGFloat = 0.1
    private static let emptyCheckLongSide: CGFloat = 128

    // Vision requests are created once and only touched on the video queue.
    private let documentRequest = VNDetectDocumentSegmentationRequest()
    private let personRequest: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()
    // EMA state is locked because reset() may come from another thread.
    private let paper = OSAllocatedUnfairLock(initialState: PaperState())

    init() {}

    /// Call on the video queue only.
    func process(_ buffer: CVPixelBuffer, trackPaper: Bool, maskHands: Bool) -> TrackerOutput {
        let frameSize = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        if !trackPaper { reset() }

        var requests: [VNRequest] = []
        if trackPaper { requests.append(documentRequest) }
        if maskHands { requests.append(personRequest) }
        guard !requests.isEmpty else { return TrackerOutput(quad: nil, handMask: nil, frameSize: frameSize) }

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        let performed = (try? handler.perform(requests)) != nil

        var quad: PaperQuad?
        if trackPaper {
            let detected = performed ? detectedQuad() : nil
            quad = paper.withLock { $0.update(with: detected) }
        }
        var handMask: CGImage?
        if maskHands, performed, let maskBuffer = personRequest.results?.first?.pixelBuffer {
            handMask = makeHandMask(frame: buffer, mask: maskBuffer)
        }
        return TrackerOutput(quad: quad, handMask: handMask, frameSize: frameSize)
    }

    /// Clears EMA and lost-frame state.
    func reset() {
        paper.withLock { $0 = PaperState() }
    }

    static func warpStencil(_ stencil: UIImage, to quad: PaperQuad, canvasSize: CGSize) -> UIImage? {
        let w = canvasSize.width, h = canvasSize.height
        guard w > 0, h > 0, stencil.size.width > 0, stencil.size.height > 0,
              let input = stencil.cgImage.map({ CIImage(cgImage: $0) }) ?? stencil.ciImage
        else { return nil }

        // Paper aspect in pixels, so the unit square is treated as paper space, not a 1:1 square.
        func length(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = (b.x - a.x) * w, dy = (b.y - a.y) * h
            return (dx * dx + dy * dy).squareRoot()
        }
        let paperWidth = (length(quad.topLeft, quad.topRight) + length(quad.bottomLeft, quad.bottomRight)) / 2
        let paperHeight = (length(quad.topLeft, quad.bottomLeft) + length(quad.topRight, quad.bottomRight)) / 2
        guard paperWidth > 1, paperHeight > 1 else { return nil }
        let paperAspect = paperWidth / paperHeight
        let stencilAspect = stencil.size.width / stencil.size.height

        // Aspect-fit inset rect in [0,1]² paper space (top-left origin).
        let inset: CGRect
        if stencilAspect > paperAspect {
            let height = paperAspect / stencilAspect
            inset = CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        } else {
            let width = stencilAspect / paperAspect
            inset = CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        }

        // Bilinear map from paper space into the quad, then to CI pixels (bottom-left origin).
        func pixel(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            let top = lerp(quad.topLeft, quad.topRight, u)
            let bottom = lerp(quad.bottomLeft, quad.bottomRight, u)
            let p = lerp(top, bottom, v)
            return CGPoint(x: p.x * w, y: (1 - p.y) * h)
        }

        let warp = CIFilter.perspectiveTransform()
        warp.inputImage = input
        warp.topLeft = pixel(inset.minX, inset.minY)
        warp.topRight = pixel(inset.maxX, inset.minY)
        warp.bottomLeft = pixel(inset.minX, inset.maxY)
        warp.bottomRight = pixel(inset.maxX, inset.maxY)
        guard let warped = warp.outputImage else { return nil }

        let canvas = CGRect(origin: .zero, size: canvasSize)
        let output = warped.composited(over: clearImage(canvas)).cropped(to: canvas)
        guard let cgImage = context.createCGImage(output, from: canvas) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Paper

    private func detectedQuad() -> PaperQuad? {
        guard let observation = documentRequest.results?.first(where: { $0.confidence >= 0.6 }) else { return nil }
        // Vision uses a bottom-left origin; flip to top-left.
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: 1 - p.y) }
        return PaperQuad(topLeft: flip(observation.topLeft), topRight: flip(observation.topRight),
                         bottomLeft: flip(observation.bottomLeft), bottomRight: flip(observation.bottomRight))
    }

    // MARK: - Hands

    private func makeHandMask(frame buffer: CVPixelBuffer, mask maskBuffer: CVPixelBuffer) -> CGImage? {
        var mask = CIImage(cvPixelBuffer: maskBuffer)
        guard mask.extent.width > 0, mask.extent.height > 0, !Self.isEmpty(mask) else { return nil }

        var frame = CIImage(cvPixelBuffer: buffer)
        let longSide = max(frame.extent.width, frame.extent.height)
        if longSide > Self.maskLongSide {
            let scale = Self.maskLongSide / longSide
            frame = frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        // Give the mask the same extent as the downscaled frame before blending.
        mask = mask.transformed(by: CGAffineTransform(scaleX: frame.extent.width / mask.extent.width,
                                                      y: frame.extent.height / mask.extent.height))

        let blend = CIFilter.blendWithMask()
        blend.inputImage = frame
        blend.backgroundImage = Self.clearImage(frame.extent)
        blend.maskImage = mask
        let target = CGRect(x: 0, y: 0, width: frame.extent.width.rounded(), height: frame.extent.height.rounded())
        guard let output = blend.outputImage?.cropped(to: target) else { return nil }
        return Self.context.createCGImage(output, from: target)
    }

    /// True when the mask's maximum value (on a small downsample) is under the threshold.
    private static func isEmpty(_ mask: CIImage) -> Bool {
        let scale = min(1, emptyCheckLongSide / max(mask.extent.width, mask.extent.height))
        let small = mask.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let maximum = CIFilter.areaMaximum()
        maximum.inputImage = small
        maximum.extent = small.extent
        guard let output = maximum.outputImage else { return true }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: output.extent.minX, y: output.extent.minY, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        return CGFloat(pixel[0]) / 255 < emptyMaskThreshold
    }

    private static func clearImage(_ rect: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: rect)
    }
}

// MARK: - Smoothing

private struct PaperState: Sendable {
    static let emaAlpha: CGFloat = 0.25
    static let deadband: CGFloat = 0.001
    static let maxLostFrames = 10

    var smoothed: PaperQuad?
    var lostFrames = 0

    /// EMA per corner with a deadband; holds the last quad for `maxLostFrames` frames after a loss.
    mutating func update(with detected: PaperQuad?) -> PaperQuad? {
        guard let detected else {
            lostFrames += 1
            if lostFrames > Self.maxLostFrames { smoothed = nil }
            return smoothed
        }
        lostFrames = 0
        guard let current = smoothed else {
            smoothed = detected
            return detected
        }
        let next = PaperQuad(
            topLeft: lerp(current.topLeft, detected.topLeft, Self.emaAlpha),
            topRight: lerp(current.topRight, detected.topRight, Self.emaAlpha),
            bottomLeft: lerp(current.bottomLeft, detected.bottomLeft, Self.emaAlpha),
            bottomRight: lerp(current.bottomRight, detected.bottomRight, Self.emaAlpha))
        // Deadband: a stationary phone keeps yielding an equal quad.
        let moved = [
            distance(next.topLeft, current.topLeft), distance(next.topRight, current.topRight),
            distance(next.bottomLeft, current.bottomLeft), distance(next.bottomRight, current.bottomRight),
        ]
        guard moved.contains(where: { $0 >= Self.deadband }) else { return current }
        smoothed = next
        return next
    }
}

private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    return (dx * dx + dy * dy).squareRoot()
}
