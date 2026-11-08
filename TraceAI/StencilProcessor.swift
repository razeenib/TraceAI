import CoreImage
import UIKit
import Vision

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

/// Photo → stencil pipeline: normalize, lift the subject (Vision), then
/// build four cumulative line/shading layers with Core Image.
enum StencilProcessor {
    /// One shared context for every render. `CIContext` is thread-safe.
    nonisolated(unsafe) private static let context = CIContext()

    /// Longest side of the working image, in pixels.
    private static let maxSide: CGFloat = 1600

    static func makeStencil(from image: UIImage) async throws -> StencilSet {
        try await Task.detached(priority: .userInitiated) {
            try process(image)
        }.value
    }

    // MARK: - Pipeline

    private static func process(_ image: UIImage) throws -> StencilSet {
        // 1. Normalize orientation + size.
        guard let upright = normalize(image) else { throw StencilError.invalidImage }
        let source = CIImage(cgImage: upright)
        let extent = source.extent

        // 2. Remove background (never fails; falls back to the original).
        let mask = foregroundMask(for: upright, extent: extent)
        let subject = mask.map { onWhite(source, mask: $0) } ?? source

        // 3. Gray.
        let gray = subject.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputContrastKey: 1.1,
        ])

        // 4. Layers.
        var shapes = lines(gray, blur: 10, threshold: 0.3)
        if let mask {
            let silhouette = mask.clampedToExtent()
                .applyingFilter("CIMorphologyGradient", parameters: [kCIInputRadiusKey: 3.0])
                .cropped(to: extent)
                .applyingFilter("CIMaskToAlpha")
            shapes = blackInk(silhouette).composited(over: shapes)
        }
        let outlines = lines(gray, blur: 4, threshold: 0.15)
        let details = lines(gray, blur: 0, threshold: 0.1)
        let shading = blackInk(
            gray.applyingFilter("CIColorPosterize", parameters: ["inputLevels": 4.0])
                .applyingFilter("CIColorInvert")
                .applyingFilter("CIMaskToAlpha"),
            alpha: 0.35
        )

        // 5. Assemble: layers[n] = L1…L(n+1) stacked source-over.
        // Each step composites onto the previous rendered layer, so every
        // line pass runs exactly once.
        var layers: [UIImage] = []
        var below: CIImage?
        for part in [shapes, outlines, details, shading] {
            let stacked = below.map { part.composited(over: $0) } ?? part
            let rendered = try render(stacked, extent: extent)
            layers.append(UIImage(cgImage: rendered))
            below = CIImage(cgImage: rendered)
        }
        return StencilSet(full: layers[2], layers: layers)
    }

    // MARK: - Steps

    /// Redraws the photo upright (applies `imageOrientation`) on white,
    /// long side ≤ `maxSide`, at scale 1.
    private static func normalize(_ image: UIImage) -> CGImage? {
        let pixels = CGSize(width: image.size.width * image.scale,
                            height: image.size.height * image.scale)
        let longest = max(pixels.width, pixels.height)
        guard longest > 0, longest.isFinite else { return nil }
        let factor = min(1, maxSide / longest)
        let size = CGSize(width: max(1, (pixels.width * factor).rounded()),
                          height: max(1, (pixels.height * factor).rounded()))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let rect = CGRect(origin: .zero, size: size)
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(rect)
            image.draw(in: rect)
        }
        return upright.cgImage
    }

    /// Foreground mask from Vision, scaled to `extent`; nil if no subject
    /// was found or the request failed.
    private static func foregroundMask(for image: CGImage, extent: CGRect) -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances, from: handler)
            let mask = CIImage(cvPixelBuffer: buffer)
            guard mask.extent.width > 0, mask.extent.height > 0 else { return nil }
            let scale = CGAffineTransform(scaleX: extent.width / mask.extent.width,
                                          y: extent.height / mask.extent.height)
            return mask.transformed(by: scale).cropped(to: extent)
        } catch {
            return nil
        }
    }

    /// Places the masked subject on a white background.
    private static func onWhite(_ image: CIImage, mask: CIImage) -> CIImage {
        let white = CIImage(color: .white).cropped(to: image.extent)
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: white,
            kCIInputMaskImageKey: mask,
        ])
    }

    /// Black lines on transparent, from a gray source.
    private static func lines(_ source: CIImage, blur: Double, threshold: Double) -> CIImage {
        var image = source.clampedToExtent()
        if blur > 0 {
            image = image.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur])
        }
        return image.applyingFilter("CILineOverlay", parameters: [
            "inputNRNoiseLevel": 0.02,
            "inputNRSharpness": 0.71,
            "inputEdgeIntensity": 1.0,
            "inputThreshold": threshold,
            "inputContrast": 50.0,
        ]).cropped(to: source.extent)
    }

    /// Turns `CIMaskToAlpha`'s white-on-transparent output into black ink
    /// with the given opacity.
    private static func blackInk(_ image: CIImage, alpha: CGFloat = 1) -> CIImage {
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": zero,
            "inputGVector": zero,
            "inputBVector": zero,
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha),
            "inputBiasVector": zero,
        ])
    }

    /// Renders RGBA8 sRGB.
    private static func render(_ image: CIImage, extent: CGRect) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = context.createCGImage(image, from: extent,
                                                  format: .RGBA8, colorSpace: space)
        else { throw StencilError.processingFailed }
        return cgImage
    }
}
