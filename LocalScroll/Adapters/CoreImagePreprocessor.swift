import CoreGraphics
import CoreImage
import Foundation
import Metal

/// Process-wide Core Image render context.
///
/// Constructing a `CIContext` allocates GPU resources, so the whole app shares a
/// single Metal-backed context across frame decoding, OCR preprocessing, and
/// optical-flow downscaling instead of creating a fresh context per frame, clip,
/// or refinement interval. `CIContext` is documented as thread-safe, so the
/// concurrent OCR task group and the decode actor can render through it safely.
public enum SharedRenderContext {
    public static let ci: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        }
        return CIContext()
    }()
}

public struct CoreImagePreprocessorConfig: Sendable {
    public var scale: Double
    public var contrast: Double
    public var brightness: Double
    public var shadowAmount: Double
    public var highlightAmount: Double

    public init(
        scale: Double = 0.75,
        contrast: Double = 1.18,
        brightness: Double = 0,
        shadowAmount: Double = 0.12,
        highlightAmount: Double = 0.9
    ) {
        self.scale = scale
        self.contrast = contrast
        self.brightness = brightness
        self.shadowAmount = shadowAmount
        self.highlightAmount = highlightAmount
    }
}

public final class CoreImagePreprocessor: FramePreprocessor {
    private let context: CIContext
    private let config: CoreImagePreprocessorConfig

    public init(
        config: CoreImagePreprocessorConfig = CoreImagePreprocessorConfig(),
        context: CIContext = SharedRenderContext.ci
    ) {
        self.config = config
        self.context = context
    }

    public func process(_ frame: VideoFrame) async throws -> VideoFrame {
        await Task.detached(priority: .userInitiated) { [config] in
            var output = frame.ciImage

            if config.scale > 0, config.scale != 1 {
                output = output.applyingFilter(
                    "CILanczosScaleTransform",
                    parameters: [
                        kCIInputScaleKey: config.scale,
                        kCIInputAspectRatioKey: 1.0,
                    ]
                )
            }

            output = output.applyingFilter(
                "CIHighlightShadowAdjust",
                parameters: [
                    "inputShadowAmount": config.shadowAmount,
                    "inputHighlightAmount": config.highlightAmount,
                ]
            )

            output = output.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputBrightnessKey: config.brightness,
                    kCIInputContrastKey: config.contrast,
                    kCIInputSaturationKey: 0.0,
                ]
            )

            // Keep the result lazy and normalized to the origin; Vision renders
            // it once during OCR instead of round-tripping through a CGImage.
            let extent = output.extent.integral
            let normalized = extent.origin == .zero
                ? output
                : output.transformed(
                    by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
                )
            let pixelExtent = normalized.extent.integral
            return VideoFrame(
                idx: frame.idx,
                timestamp: frame.timestamp,
                ciImage: normalized,
                pixelWidth: Int(pixelExtent.width),
                pixelHeight: Int(pixelExtent.height)
            )
        }.value
    }
}

public enum CoreImagePreprocessorError: Error, LocalizedError {
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .renderFailed:
            return "Core Image could not render the preprocessed frame."
        }
    }
}
