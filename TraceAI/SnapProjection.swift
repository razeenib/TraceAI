import QuartzCore
import SwiftUI

/// Pins a stencil view to the tracked paper with a homography, so the GPU warps the
/// full-resolution image and nothing is re-rendered when the quad moves.
enum SnapProjection {
    /// Transform for `.projectionEffect` on a view of `viewSize` laid out at the container's
    /// top-left corner. `viewSize` must have the stencil's aspect ratio. `frameSize` is the
    /// upright camera frame, aspect-filled into `containerSize` exactly like the preview.
    static func transform(quad: PaperQuad, viewSize: CGSize,
                          frameSize: CGSize, containerSize: CGSize) -> ProjectionTransform? {
        guard viewSize.width > 0, viewSize.height > 0, frameSize.width > 0, frameSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return nil }

        // Normalized camera-frame point → container point (aspect fill, centered).
        let fill = max(containerSize.width / frameSize.width, containerSize.height / frameSize.height)
        let shown = CGSize(width: frameSize.width * fill, height: frameSize.height * fill)
        let origin = CGPoint(x: (containerSize.width - shown.width) / 2,
                             y: (containerSize.height - shown.height) / 2)
        func screen(_ p: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + p.x * shown.width, y: origin.y + p.y * shown.height)
        }
        let tl = screen(quad.topLeft), tr = screen(quad.topRight)
        let br = screen(quad.bottomRight), bl = screen(quad.bottomLeft)

        // Aspect-fit the stencil inside the paper, in unit paper space.
        let paperWidth = (length(tl, tr) + length(bl, br)) / 2
        let paperHeight = (length(tl, bl) + length(tr, br)) / 2
        guard paperWidth > 1, paperHeight > 1 else { return nil }
        let paperAspect = paperWidth / paperHeight
        let stencilAspect = viewSize.width / viewSize.height
        let inset: CGRect
        if stencilAspect > paperAspect {
            let height = paperAspect / stencilAspect
            inset = CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        } else {
            let width = stencilAspect / paperAspect
            inset = CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        }

        // Paper space → screen (perspective-correct), then view rect → those four corners.
        guard let paper = Homography(tl, tr, br, bl),
              let h = Homography(paper.map(inset.minX, inset.minY), paper.map(inset.maxX, inset.minY),
                                 paper.map(inset.maxX, inset.maxY), paper.map(inset.minX, inset.maxY))
        else { return nil }

        var m = CATransform3DIdentity
        m.m11 = h.a / viewSize.width;  m.m12 = h.d / viewSize.width;  m.m14 = h.g / viewSize.width
        m.m21 = h.b / viewSize.height; m.m22 = h.e / viewSize.height; m.m24 = h.h / viewSize.height
        m.m41 = h.c;                   m.m42 = h.f;                   m.m44 = 1
        return ProjectionTransform(m)
    }

    private static func length(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Maps the unit square to a quad: x' = (a·u + b·v + c) / (g·u + h·v + 1), same for y' with d, e, f.
private struct Homography {
    let a, b, c, d, e, f, g, h: CGFloat

    /// Corners in order (0,0), (1,0), (1,1), (0,1). Nil for degenerate or non-convex quads.
    init?(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) {
        let dx1 = p1.x - p2.x, dx2 = p3.x - p2.x, sx = p0.x - p1.x + p2.x - p3.x
        let dy1 = p1.y - p2.y, dy2 = p3.y - p2.y, sy = p0.y - p1.y + p2.y - p3.y
        let den = dx1 * dy2 - dx2 * dy1
        guard abs(den) > 1e-9 else { return nil }
        let g = (sx * dy2 - dx2 * sy) / den
        let h = (dx1 * sy - sx * dy1) / den
        // The divisor must stay positive at every corner, or the warp folds over.
        guard g + 1 > 1e-6, h + 1 > 1e-6, g + h + 1 > 1e-6 else { return nil }
        self.g = g; self.h = h
        a = p1.x - p0.x + g * p1.x; b = p3.x - p0.x + h * p3.x; c = p0.x
        d = p1.y - p0.y + g * p1.y; e = p3.y - p0.y + h * p3.y; f = p0.y
    }

    func map(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        let w = g * u + h * v + 1
        return CGPoint(x: (a * u + b * v + c) / w, y: (d * u + e * v + f) / w)
    }
}
