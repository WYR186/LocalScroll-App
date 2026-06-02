import CoreGraphics
import CoreImage
import Foundation

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
        context: CIContext = CIContext()
    ) {
        self.config = config
        self.context = context
    }

    public func process(_ frame: VideoFrame) async throws -> VideoFrame {
        try await Task.detached(priority: .userInitiated) { [config, context] in
            let input = CIImage(cgImage: frame.image)
            var output = input

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

            let extent = output.extent.integral
            guard let image = context.createCGImage(output, from: extent) else {
                throw CoreImagePreprocessorError.renderFailed
            }

            return VideoFrame(idx: frame.idx, timestamp: frame.timestamp, image: image)
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
