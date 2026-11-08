import CoreGraphics
import CoreVideo
import UIKit

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
    init() {}

    // STUB (Phase 0). Phase 4B adds document segmentation, EMA smoothing and the person mask.
    /// Call on the video queue only.
    func process(_ buffer: CVPixelBuffer, trackPaper: Bool, maskHands: Bool) -> TrackerOutput {
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        return TrackerOutput(quad: nil, handMask: nil, frameSize: size)
    }

    /// Clears EMA and lost-frame state.
    func reset() {}

    static func warpStencil(_ stencil: UIImage, to quad: PaperQuad, canvasSize: CGSize) -> UIImage? {
        nil
    }
}
