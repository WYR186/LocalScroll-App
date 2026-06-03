import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

public enum AVAssetVideoSourceError: Error, LocalizedError {
    case invalidFPS(Double)
    case invalidTimeRange(Double, Double?)
    case emptyAsset(URL)
    case noVideoTrack(URL)
    case cannotCreateReader(URL)
    case cannotAddReaderOutput(URL)
    case readerFailed(String)
    case missingImageBuffer
    case imageConversionFailed
    case frameGenerationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidFPS(let fps):
            return "Target FPS must be greater than zero; got \(fps)."
        case .invalidTimeRange(let start, let end):
            if let end {
                return "Invalid video sampling range: \(start)s to \(end)s."
            }
            return "Invalid video sampling start time: \(start)s."
        case .emptyAsset(let url):
            return "The selected video has no readable duration: \(url.lastPathComponent)."
        case .noVideoTrack(let url):
            return "The selected asset has no video track: \(url.lastPathComponent)."
        case .cannotCreateReader(let url):
            return "Could not create a sequential video reader for \(url.lastPathComponent)."
        case .cannotAddReaderOutput(let url):
            return "Could not attach a video track output for \(url.lastPathComponent)."
        case .readerFailed(let reason):
            return "Video reader failed: \(reason)"
        case .missingImageBuffer:
            return "The video sample did not contain an image buffer."
        case .imageConversionFailed:
            return "Could not convert the decoded video frame to an image."
        case .frameGenerationFailed:
            return "AVFoundation did not return a generated frame."
        }
    }
}

public final class AVAssetVideoSource: VideoSource {
    public let sourceURL: URL

    private let asset: AVURLAsset

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
        frames(targetFPS: targetFPS, startSeconds: 0, endSeconds: nil)
    }

    public func frames(
        targetFPS: Double,
        startSeconds: Double,
        endSeconds: Double?
    ) -> AsyncThrowingStream<VideoFrame, Error> {
        let iterator = AVAssetFrameIterator(
            asset: asset,
            sourceURL: sourceURL,
            targetFPS: targetFPS,
            startSeconds: startSeconds,
            endSeconds: endSeconds
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
    private let startSeconds: Double
    private let endSeconds: Double?

    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var preferredTransform: CGAffineTransform = .identity
    private var context: CIContext?
    private var frameCount: Int?
    private var baseIndex = 0
    private var nextIndex = 0
    private var finished = false

    init(
        asset: AVURLAsset,
        sourceURL: URL,
        targetFPS: Double,
        startSeconds: Double,
        endSeconds: Double?
    ) {
        self.asset = asset
        self.sourceURL = sourceURL
        self.targetFPS = targetFPS
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    func next() async throws -> VideoFrame? {
        try Task.checkCancellation()
        try await prepareIfNeeded()

        guard !finished, let output, let reader, let frameCount, nextIndex < frameCount else {
            finishReader()
            return nil
        }

        let requestedSeconds = max(0, startSeconds) + Double(nextIndex) / targetFPS
        let epsilon = max(0.000_001, 0.25 / targetFPS)

        while !finished {
            try Task.checkCancellation()
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                if reader.status == .failed || reader.status == .cancelled {
                    throw AVAssetVideoSourceError.readerFailed(
                        reader.error?.localizedDescription ?? "\(reader.status.rawValue)"
                    )
                }
                finished = true
                finishReader()
                return nil
            }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard timestamp.isFinite else { continue }
            guard timestamp + epsilon >= requestedSeconds else { continue }

            let idx = baseIndex + nextIndex
            nextIndex += 1
            let image = try makeCGImage(from: sampleBuffer)
            return VideoFrame(idx: idx, timestamp: timestamp, image: image)
        }

        finishReader()
        return nil
    }

    private func prepareIfNeeded() async throws {
        guard reader == nil else { return }

        guard targetFPS.isFinite, targetFPS > 0 else {
            throw AVAssetVideoSourceError.invalidFPS(targetFPS)
        }
        guard startSeconds.isFinite, startSeconds >= 0 else {
            throw AVAssetVideoSourceError.invalidTimeRange(startSeconds, endSeconds)
        }
        if let endSeconds {
            guard endSeconds.isFinite, endSeconds > startSeconds else {
                throw AVAssetVideoSourceError.invalidTimeRange(startSeconds, endSeconds)
            }
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

        let track = tracks[0]
        let rangeStart = min(startSeconds, seconds)
        let rangeEnd = min(endSeconds ?? seconds, seconds)
        guard rangeEnd > rangeStart else {
            frameCount = 0
            finished = true
            return
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AVAssetVideoSourceError.cannotCreateReader(sourceURL)
        }

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw AVAssetVideoSourceError.cannotAddReaderOutput(sourceURL)
        }
        reader.add(output)
        if rangeStart > 0 || rangeEnd < seconds {
            let start = CMTime(seconds: rangeStart, preferredTimescale: 600)
            let duration = CMTime(seconds: rangeEnd - rangeStart, preferredTimescale: 600)
            reader.timeRange = CMTimeRange(start: start, duration: duration)
        }
        guard reader.startReading() else {
            throw AVAssetVideoSourceError.readerFailed(
                reader.error?.localizedDescription ?? "\(reader.status.rawValue)"
            )
        }

        self.reader = reader
        self.output = output
        self.preferredTransform = try await track.load(.preferredTransform)
        self.context = CIContext()
        self.baseIndex = Int((rangeStart * targetFPS).rounded(.toNearestOrAwayFromZero))
        self.frameCount = max(1, Int(ceil((rangeEnd - rangeStart) * targetFPS)))
    }

    private func makeCGImage(from sampleBuffer: CMSampleBuffer) throws -> CGImage {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw AVAssetVideoSourceError.missingImageBuffer
        }
        guard let context else {
            throw AVAssetVideoSourceError.imageConversionFailed
        }

        return try autoreleasepool {
            let input = CIImage(cvPixelBuffer: imageBuffer)
            let transformed = input.transformed(by: preferredTransform)
            let extent = transformed.extent.integral
            let normalized = transformed.transformed(
                by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
            )
            let renderExtent = normalized.extent.integral

            guard let image = context.createCGImage(normalized, from: renderExtent) else {
                throw AVAssetVideoSourceError.imageConversionFailed
            }
            return image
        }
    }

    private func finishReader() {
        output = nil
        if reader?.status == .reading {
            reader?.cancelReading()
        }
        reader = nil
        context = nil
    }
}
