import UIKit

/// Three built-in sketches drawn in code (no image assets).
enum SampleSketch: String, CaseIterable, Identifiable, Sendable {
    case cat, flower, house

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cat: "Cat"
        case .flower: "Flower"
        case .house: "House"
        }
    }

    // STUB (Phase 0). Phase 2 draws the real 4-layer sketches.
    func makeStencilSet(size: CGSize = CGSize(width: 1024, height: 1024)) -> StencilSet {
        let blank = UIImage()
        return StencilSet(full: blank, layers: Array(repeating: blank, count: 4))
    }
}
