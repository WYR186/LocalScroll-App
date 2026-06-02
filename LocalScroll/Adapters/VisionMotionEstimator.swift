import CoreGraphics
import CoreVideo
import Foundation
import Vision

public struct VisionMotionEstimatorConfig: Sendable {
    public var accuracy: VNGenerateOpticalFlowRequest.ComputationAccuracy
    public var movingPixelThreshold: Float
    public var minimumMovingSamples: Int
    public var maximumSamples: Int

    public init(
        accuracy: VNGenerateOpticalFlowRequest.ComputationAccuracy = .medium,
        movingPixelThreshold: Float = 0.5,
        minimumMovingSamples: Int = 100,
        maximumSamples: Int = 50_000
    ) {
        self.accuracy = accuracy
        self.movingPixelThreshold = movingPixelThreshold
        self.minimumMovingSamples = minimumMovingSamples
        self.maximumSamples = maximumSamples
    }
}

public final class VisionMotionEstimator: MotionEstimator {
    private let config: VisionMotionEstimatorConfig

    public init(config: VisionMotionEstimatorConfig = VisionMotionEstimatorConfig()) {
        self.config = config
    }

    public func estimateDy(previous: VideoFrame, current: VideoFrame) async throws -> Double {
        try await Task.detached(priority: .userInitiated) { [config] in
            guard previous.width == current.width, previous.height == current.height else {
                throw VisionMotionEstimatorError.mismatchedFrameSize
            }

            let request = VNGenerateOpticalFlowRequest(
                targetedCGImage: current.image,
                options: [:],
                completionHandler: nil
            )
            request.computationAccuracy = config.accuracy
            request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float

            let handler = VNImageRequestHandler(cgImage: previous.image, orientation: .up, options: [:])
            try handler.perform([request])

            guard let observation = request.results?.first else {
                throw VisionMotionEstimatorError.noObservation
            }

            return try medianDy(
                from: observation.pixelBuffer,
                movingPixelThreshold: config.movingPixelThreshold,
                minimumMovingSamples: config.minimumMovingSamples,
                maximumSamples: config.maximumSamples
            )
        }.value
    }
}

public enum VisionMotionEstimatorError: Error, LocalizedError {
    case mismatchedFrameSize
    case noObservation
    case unsupportedPixelFormat(OSType)
    case unreadablePixelBuffer

    public var errorDescription: String? {
        switch self {
        case .mismatchedFrameSize:
            return "Optical flow requires consecutive frames with the same dimensions."
        case .noObservation:
            return "Vision did not return an optical-flow observation."
        case .unsupportedPixelFormat(let format):
            return "Unsupported optical-flow pixel format: \(format)."
        case .unreadablePixelBuffer:
            return "Could not read the optical-flow pixel buffer."
        }
    }
}

private func medianDy(
    from pixelBuffer: CVPixelBuffer,
    movingPixelThreshold: Float,
    minimumMovingSamples: Int,
    maximumSamples: Int
) throws -> Double {
    let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
    guard format == kCVPixelFormatType_TwoComponent32Float else {
        throw VisionMotionEstimatorError.unsupportedPixelFormat(format)
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw VisionMotionEstimatorError.unreadablePixelBuffer
    }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let totalPixels = max(1, width * height)
    let sampleStride = max(1, totalPixels / max(1, maximumSamples))

    var moving: [Double] = []
    var all: [Double] = []
    moving.reserveCapacity(min(maximumSamples, totalPixels))
    all.reserveCapacity(min(maximumSamples, totalPixels))

    var seen = 0
    for y in 0..<height {
        let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
        for x in 0..<width {
            defer { seen += 1 }
            guard seen % sampleStride == 0 else { continue }

            let dy = row[x * 2 + 1]
            let value = Double(dy)
            all.append(value)
            if abs(dy) > movingPixelThreshold {
                moving.append(value)
            }
        }
    }

    if moving.count >= minimumMovingSamples {
        return median(moving)
    }
    guard !all.isEmpty else { return 0 }
    return all.reduce(0, +) / Double(all.count)
}

private func median(_ values: [Double]) -> Double {
    if values.isEmpty { return 0 }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    if sorted.count % 2 == 1 {
        return sorted[mid]
    }
    return (sorted[mid - 1] + sorted[mid]) / 2
}
