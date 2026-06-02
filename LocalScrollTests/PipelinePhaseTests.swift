import CoreGraphics
import Foundation
import LocalScrollCore
import Testing
@testable import LocalScroll

struct PipelinePhaseTests {
    @Test func scrollPipelineDeduplicatesOverlappingFrames() async throws {
        let source = MockVideoSource(frameCount: 3)
        let ocr = MockOCRBackend(linesByFrame: [
            0: [
                Line(text: "Header", bbox: BBox(x: 0, y: 0, w: 80, h: 12), confidence: 1),
                Line(text: "Alpha receipt", bbox: BBox(x: 0, y: 20, w: 80, h: 12), confidence: 1),
            ],
            1: [
                Line(text: "Alpha receipt", bbox: BBox(x: 0, y: 0, w: 80, h: 12), confidence: 1),
                Line(text: "Beta invoice", bbox: BBox(x: 0, y: 20, w: 80, h: 12), confidence: 1),
            ],
            2: [
                Line(text: "Beta invoice", bbox: BBox(x: 0, y: 0, w: 80, h: 12), confidence: 1),
                Line(text: "Gamma summary", bbox: BBox(x: 0, y: 20, w: 80, h: 12), confidence: 1),
            ],
        ])
        let pipeline = Pipeline(video: source, ocr: ocr, config: PipelineConfig(fps: 1.0))

        var progressEvents: [PipelineProgress] = []
        let transcript = try await pipeline.run { progress in
            progressEvents.append(progress)
        }

        #expect(transcript.lines == ["Header", "Alpha receipt", "Beta invoice", "Gamma summary"])
        #expect(transcript.sourceVideo == source.sourceURL)
        #expect(progressEvents.map(\.processedFrames) == [1, 2, 3])
        #expect(progressEvents.last?.fractionCompleted == 1)
    }

    @Test func adaptivePipelineSkipsPausedFrames() async throws {
        let source = MockVideoSource(frameCount: 3)
        let ocr = MockOCRBackend(linesByFrame: [
            0: [Line(text: "First unique row", bbox: BBox(x: 0, y: 0, w: 80, h: 12), confidence: 1)],
            1: [Line(text: "Paused duplicate row", bbox: BBox(x: 0, y: 0, w: 80, h: 12), confidence: 1)],
            2: [Line(text: "Second unique row", bbox: BBox(x: 0, y: 0, w: 80, h: 12), confidence: 1)],
        ])
        let motion = MockMotionEstimator(dys: [0, 10])
        let pipeline = Pipeline(
            video: source,
            ocr: ocr,
            motion: motion,
            config: PipelineConfig(
                fps: 1.0,
                adaptive: true
            )
        )

        var progressEvents: [PipelineProgress] = []
        let transcript = try await pipeline.run { progress in
            progressEvents.append(progress)
        }

        #expect(transcript.lines == ["First unique row", "Second unique row"])
        #expect(ocr.detectedFrameIndices == [0, 2])
        #expect(progressEvents.map(\.skippedFrames) == [0, 1, 1])
        #expect(progressEvents[1].scrollState == .paused)
    }

    @Test func captionModeCollapsesIncrementalLines() async throws {
        let source = MockVideoSource(frameCount: 3)
        let ocr = MockOCRBackend(linesByFrame: [
            0: [Line(text: "Hello", bbox: BBox(x: 0, y: 0, w: 80, h: 12), confidence: 1)],
            1: [Line(text: "Hello world", bbox: BBox(x: 0, y: 0, w: 80, h: 12), confidence: 1)],
            2: [Line(text: "Hello world today", bbox: BBox(x: 0, y: 0, w: 80, h: 12), confidence: 1)],
        ])
        let pipeline = Pipeline(
            video: source,
            ocr: ocr,
            config: PipelineConfig(
                fps: 1.0,
                stitchMode: .caption
            )
        )

        let transcript = try await pipeline.run()

        #expect(transcript.lines == ["Hello world today"])
    }

    @Test func fourMinuteEquivalentPipelineCompletesWithoutFrameAccumulation() async throws {
        let frameCount = 480
        let source = MockVideoSource(frameCount: frameCount)
        let ocr = SequentialOCRBackend()
        let pipeline = Pipeline(
            video: source,
            ocr: ocr,
            config: PipelineConfig(fps: 2.0)
        )

        var lastProgress: PipelineProgress?
        let transcript = try await pipeline.run { progress in
            lastProgress = progress
        }

        #expect(transcript.lines.count == frameCount)
        #expect(lastProgress?.processedFrames == frameCount)
        #expect(lastProgress?.fractionCompleted == 1)
    }

    @Test func pipelineCancellationStopsPromptly() async throws {
        let source = StreamingMockVideoSource(frameCount: 1_000, frameDelayNanoseconds: 1_000_000)
        let ocr = SlowOCRBackend(delayNanoseconds: 20_000_000)
        let pipeline = Pipeline(
            video: source,
            ocr: ocr,
            config: PipelineConfig(fps: 10.0)
        )

        let task = Task {
            try await pipeline.run()
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
            #expect(Bool(false), "Pipeline should throw CancellationError after cancellation.")
        } catch is CancellationError {
            #expect(ocr.detectCount < 1_000)
        }
    }
}

private final class MockVideoSource: VideoSource {
    let sourceURL = URL(fileURLWithPath: "/tmp/mock.mov")
    private let frameCount: Int
    private let image: CGImage

    init(frameCount: Int) {
        self.frameCount = frameCount
        self.image = makeOnePixelImage()
    }

    func durationSeconds() async throws -> Double {
        Double(frameCount)
    }

    func frames(targetFPS: Double) -> AsyncThrowingStream<VideoFrame, Error> {
        AsyncThrowingStream { continuation in
            for idx in 0..<frameCount {
                continuation.yield(VideoFrame(idx: idx, timestamp: Double(idx), image: image))
            }
            continuation.finish()
        }
    }
}

private final class MockOCRBackend: OCRBackend {
    private let linesByFrame: [Int: [Line]]
    private(set) var detectedFrameIndices: [Int] = []

    init(linesByFrame: [Int: [Line]]) {
        self.linesByFrame = linesByFrame
    }

    func detect(in frame: VideoFrame) async throws -> [Line] {
        detectedFrameIndices.append(frame.idx)
        return linesByFrame[frame.idx] ?? []
    }
}

private final class SequentialOCRBackend: OCRBackend {
    func detect(in frame: VideoFrame) async throws -> [Line] {
        [
            Line(
                text: "Unique frame \(frame.idx)",
                bbox: BBox(x: 0, y: 0, w: 80, h: 12),
                confidence: 1
            ),
        ]
    }
}

private final class SlowOCRBackend: OCRBackend {
    private let delayNanoseconds: UInt64
    private let lock = NSLock()
    private var count = 0

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    var detectCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func detect(in frame: VideoFrame) async throws -> [Line] {
        lock.lock()
        count += 1
        lock.unlock()

        try await Task.sleep(nanoseconds: delayNanoseconds)
        return [
            Line(
                text: "Slow frame \(frame.idx)",
                bbox: BBox(x: 0, y: 0, w: 80, h: 12),
                confidence: 1
            ),
        ]
    }
}

private final class MockMotionEstimator: MotionEstimator {
    private let dys: [Double]
    private var index = 0

    init(dys: [Double]) {
        self.dys = dys
    }

    func estimateDy(previous: VideoFrame, current: VideoFrame) async throws -> Double {
        defer { index += 1 }
        return dys[min(index, dys.count - 1)]
    }
}

private final class StreamingMockVideoSource: VideoSource {
    let sourceURL = URL(fileURLWithPath: "/tmp/streaming-mock.mov")
    private let frameCount: Int
    private let frameDelayNanoseconds: UInt64
    private let image: CGImage

    init(frameCount: Int, frameDelayNanoseconds: UInt64) {
        self.frameCount = frameCount
        self.frameDelayNanoseconds = frameDelayNanoseconds
        self.image = makeOnePixelImage()
    }

    func durationSeconds() async throws -> Double {
        Double(frameCount)
    }

    func frames(targetFPS: Double) -> AsyncThrowingStream<VideoFrame, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for idx in 0..<frameCount {
                        try Task.checkCancellation()
                        continuation.yield(VideoFrame(idx: idx, timestamp: Double(idx), image: image))
                        try await Task.sleep(nanoseconds: frameDelayNanoseconds)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
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

private func makeOnePixelImage() -> CGImage {
    let data = [UInt8](repeating: 255, count: 4)
    let provider = CGDataProvider(data: Data(data) as CFData)!
    return CGImage(
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}
