import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import LocalScrollCore
import Vision

public enum VisionOCRBackendError: Error, LocalizedError {
    case noCandidateText

    public var errorDescription: String? {
        switch self {
        case .noCandidateText:
            return "Vision returned text observations without recognized text candidates."
        }
    }
}

public final class VisionOCRBackend: OCRBackend {
    public var recognitionLanguages: [String]
    public var recognitionLevel: VNRequestTextRecognitionLevel
    public var usesLanguageCorrection: Bool
    public var minimumTextHeight: Float?
    public var automaticallyDetectsLanguage: Bool

    public init(
        recognitionLanguages: [String] = [],
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        usesLanguageCorrection: Bool = true,
        minimumTextHeight: Float? = nil,
        automaticallyDetectsLanguage: Bool = true
    ) {
        self.recognitionLanguages = recognitionLanguages
        self.recognitionLevel = recognitionLevel
        self.usesLanguageCorrection = usesLanguageCorrection
        self.minimumTextHeight = minimumTextHeight
        self.automaticallyDetectsLanguage = automaticallyDetectsLanguage
    }

    public func detect(in frame: VideoFrame) async throws -> [Line] {
        try await Task.detached(priority: .userInitiated) { [recognitionLanguages, recognitionLevel, usesLanguageCorrection, minimumTextHeight, automaticallyDetectsLanguage] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = recognitionLevel
            if recognitionLanguages.isEmpty {
                request.automaticallyDetectsLanguage = automaticallyDetectsLanguage
            } else {
                request.recognitionLanguages = recognitionLanguages
                request.automaticallyDetectsLanguage = false
            }
            request.usesLanguageCorrection = usesLanguageCorrection
            if let minimumTextHeight {
                request.minimumTextHeight = minimumTextHeight
            }

            let handler = VNImageRequestHandler(
                ciImage: frame.ciImage,
                orientation: .up,
                options: [:]
            )
            try handler.perform([request])

            let observations = request.results ?? []
            let lines = observations.compactMap { observation -> Line? in
                guard let candidate = observation.topCandidates(1).first else {
                    return nil
                }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }

                let bbox = visionBoundingBoxToBBox(
                    observation.boundingBox,
                    imageWidth: frame.width,
                    imageHeight: frame.height
                )

                return Line(
                    text: text,
                    bbox: bbox,
                    confidence: Double(candidate.confidence)
                )
            }

            return lines.sorted { lhs, rhs in
                if lhs.bbox.y == rhs.bbox.y {
                    return lhs.bbox.x < rhs.bbox.x
                }
                return lhs.bbox.y < rhs.bbox.y
            }
        }.value
    }
}

/// Convert Vision's normalized, lower-left-origin rect to LocalScroll's
/// top-left pixel-coordinate `BBox`.
public func visionBoundingBoxToBBox(
    _ rect: CGRect,
    imageWidth: Int,
    imageHeight: Int
) -> BBox {
    let width = max(0, imageWidth)
    let height = max(0, imageHeight)

    let minX = clamp(rect.minX, min: 0, max: 1)
    let maxX = clamp(rect.maxX, min: 0, max: 1)
    let minY = clamp(rect.minY, min: 0, max: 1)
    let maxY = clamp(rect.maxY, min: 0, max: 1)

    let x = Int((minX * Double(width)).rounded(.down))
    let y = Int(((1.0 - maxY) * Double(height)).rounded(.down))
    let w = Int(((maxX - minX) * Double(width)).rounded(.toNearestOrAwayFromZero))
    let h = Int(((maxY - minY) * Double(height)).rounded(.toNearestOrAwayFromZero))

    return BBox(
        x: clampedInt(x, lower: 0, upper: width),
        y: clampedInt(y, lower: 0, upper: height),
        w: clampedInt(w, lower: 0, upper: max(0, width - x)),
        h: clampedInt(h, lower: 0, upper: max(0, height - y))
    )
}

private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
    Swift.min(Swift.max(value, lower), upper)
}

private func clampedInt(_ value: Int, lower: Int, upper: Int) -> Int {
    Swift.min(Swift.max(value, lower), upper)
}
