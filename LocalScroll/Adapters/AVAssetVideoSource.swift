import AVFoundation
import CoreGraphics
import Foundation

public enum AVAssetVideoSourceError: Error, LocalizedError {
    case invalidFPS(Double)
    case emptyAsset(URL)
    case noVideoTrack(URL)
    case frameGenerationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidFPS(let fps):
            return "Target FPS must be greater than zero; got \(fps)."
        case .emptyAsset(let url):
            return "The selected video has no readable duration: \(url.lastPathComponent)."
        case .noVideoTrack(let url):
            return "The selected asset has no video track: \(url.lastPathComponent)."
        case .frameGenerationFailed:
            return "AVFoundation did not return a generated frame."
        }
    }
}

public final class AVAssetVideoSource: VideoSource {
    public let sourceURL: URL

    private let asset: AVURLAsset
    private let preferredTimescale: CMTimeScale = 600

    public init(url: URL) {
        self.sourceURL = url
        self.asset = AVURLAsset(url: url)
    }

    public func durationSeconds() async throws -> Double {
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw AVAssetVideoSourceError.emptyAsset(sourceURL)
        }
        return seconds
    }

    public func frames(targetFPS: Double) -> AsyncThrowingStream<VideoFrame, Error> {
        let iterator = AVAssetFrameIterator(
            asset: asset,
            sourceURL: sourceURL,
            targetFPS: targetFPS,
            preferredTimescale: preferredTimescale
        )

        return AsyncThrowingStream {
            try await iterator.next()
        }
    }
}

private actor AVAssetFrameIterator {
    private let asset: AVURLAsset
    private let sourceURL: URL
    private let targetFPS: Double
    private let preferredTimescale: CMTimeScale

    private var generator: AVAssetImageGenerator?
    private var frameCount: Int?
    private var nextIndex = 0

    init(
        asset: AVURLAsset,
        sourceURL: URL,
        targetFPS: Double,
        preferredTimescale: CMTimeScale
    ) {
        self.asset = asset
        self.sourceURL = sourceURL
        self.targetFPS = targetFPS
        self.preferredTimescale = preferredTimescale
    }

    func next() async throws -> VideoFrame? {
        try Task.checkCancellation()
        try await prepareIfNeeded()

        guard let generator, let frameCount, nextIndex < frameCount else {
            generator?.cancelAllCGImageGeneration()
            return nil
        }

        let idx = nextIndex
        nextIndex += 1

        return try autoreleasepool {
            let requestedSeconds = Double(idx) / targetFPS
            let requestedTime = CMTime(
                seconds: requestedSeconds,
                preferredTimescale: preferredTimescale
            )
            var actualTime = CMTime.zero
            let image = try generator.copyCGImage(at: requestedTime, actualTime: &actualTime)
            let timestamp = actualTime.seconds.isFinite ? actualTime.seconds : requestedSeconds

            return VideoFrame(idx: idx, timestamp: timestamp, image: image)
        }
    }

    private func prepareIfNeeded() async throws {
        guard generator == nil else { return }

        guard targetFPS.isFinite, targetFPS > 0 else {
            throw AVAssetVideoSourceError.invalidFPS(targetFPS)
        }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else {
            throw AVAssetVideoSourceError.noVideoTrack(sourceURL)
        }

        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw AVAssetVideoSourceError.emptyAsset(sourceURL)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        self.generator = generator
        self.frameCount = max(1, Int(ceil(seconds * targetFPS)))
    }
}
