import AVFoundation
import CoreGraphics
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Generates a JPEG thumbnail for a video, reusing the same `AVAssetImageGenerator`
/// approach as `AVAssetVideoSource`.
enum VideoThumbnail {
    /// Target width of the generated thumbnail in pixels.
    static let targetWidth: CGFloat = 400

    enum ThumbnailError: Error {
        case generationFailed
        case encodingFailed
    }

    /// Generate a thumbnail taken ~10% into the video (skips leading black frames).
    static func generate(url: URL) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let seconds = duration.isFinite && duration > 0 ? duration * 0.1 : 0

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: targetWidth, height: targetWidth * 4)

        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let cgImage: CGImage
        do {
            cgImage = try await generator.image(at: time).image
        } catch {
            // Fall back to the very first frame.
            cgImage = try await generator.image(at: .zero).image
        }

        guard let data = encodeJPEG(cgImage) else {
            throw ThumbnailError.encodingFailed
        }
        return data
    }

    private static func encodeJPEG(_ cgImage: CGImage) -> Data? {
#if os(iOS)
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
#elseif os(macOS)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
#else
        return nil
#endif
    }
}

/// Formats a duration in seconds as `m:ss` (or `h:mm:ss`).
enum DurationFormat {
    static func string(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
