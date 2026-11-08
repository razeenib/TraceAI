import UIKit

/// Black-on-transparent stencil images for one drawing.
struct StencilSet: Sendable {
    /// Free stencil: line art only (equals `layers[2]`).
    let full: UIImage
    /// Exactly 4 cumulative layers: 1 Shapes, 2 Outlines, 3 Details, 4 Shading.
    let layers: [UIImage]
}

enum StencilError: Error {
    case invalidImage
    case processingFailed
}

enum StencilProcessor {
    // STUB (Phase 0). Phase 3 replaces this with the Vision + CoreImage pipeline.
    static func makeStencil(from image: UIImage) async throws -> StencilSet {
        StencilSet(full: image, layers: Array(repeating: image, count: 4))
    }
}
