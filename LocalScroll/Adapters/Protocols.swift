import CoreGraphics
import Foundation
import LocalScrollCore

/// A decoded video frame backed by an in-memory image.
///
/// This intentionally lives in the app adapter layer instead of
/// `LocalScrollCore.Frame`, so the pure algorithm target stays free of
/// AVFoundation/CoreGraphics/CoreVideo imports.
public struct VideoFrame {
    public let idx: Int
    public let timestamp: Double
    public let image: CGImage

    public init(idx: Int, timestamp: Double, image: CGImage) {
        self.idx = idx
        self.timestamp = timestamp
        self.image = image
    }

    public var width: Int { image.width }
    public var height: Int { image.height }
}

public protocol VideoSource {
    var sourceURL: URL { get }

    /// Duration in seconds, loaded from the underlying asset.
    func durationSeconds() async throws -> Double

    /// Sample frames at the requested fixed FPS.
    ///
    /// Implementations yield contiguous zero-based indices and monotonic
    /// timestamps. Cancellation stops extraction promptly.
    func frames(targetFPS: Double) -> AsyncThrowingStream<VideoFrame, Error>

    /// Sample frames at the requested fixed FPS inside a time range.
    ///
    /// `endSeconds == nil` means "until the end of the video". Implementations
    /// that can seek efficiently should avoid decoding unrelated ranges.
    func frames(
        targetFPS: Double,
        startSeconds: Double,
        endSeconds: Double?
    ) -> AsyncThrowingStream<VideoFrame, Error>
}

public extension VideoSource {
    func frames(
        targetFPS: Double,
        startSeconds: Double,
        endSeconds: Double?
    ) -> AsyncThrowingStream<VideoFrame, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let clampedStart = max(0, startSeconds)
                    for try await frame in frames(targetFPS: targetFPS) {
                        try Task.checkCancellation()
                        guard frame.timestamp >= clampedStart else { continue }
                        if let endSeconds, frame.timestamp > endSeconds {
                            break
                        }
                        continuation.yield(frame)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

public protocol OCRBackend {
    /// Detect text lines in one decoded frame.
    func detect(in frame: VideoFrame) async throws -> [Line]
}

public protocol MotionEstimator {
    /// Estimate vertical scroll displacement between two frames.
    ///
    /// Sign convention follows `Scheduler`: positive dy means forward scroll.
    func estimateDy(previous: VideoFrame, current: VideoFrame) async throws -> Double
}

public protocol FramePreprocessor {
    /// Improve a frame before OCR while preserving the frame index/timestamp.
    func process(_ frame: VideoFrame) async throws -> VideoFrame
}

public enum TranscriptCleanupAvailability: Equatable, Sendable {
    case available
    case unavailable(String)
}

public struct TranscriptCleanupResult: Equatable, Sendable {
    public let rawTranscript: Transcript
    public let cleanedTranscript: Transcript
    public let didChange: Bool

    public init(rawTranscript: Transcript, cleanedTranscript: Transcript) {
        self.rawTranscript = rawTranscript
        self.cleanedTranscript = cleanedTranscript
        self.didChange = rawTranscript.lines != cleanedTranscript.lines
    }
}

public protocol TranscriptCleaner {
    var availability: TranscriptCleanupAvailability { get }

    /// Return a cleaned transcript while preserving the raw transcript for callers.
    func cleanup(_ transcript: Transcript) async throws -> TranscriptCleanupResult
}
