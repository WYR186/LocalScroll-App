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
        let transcript = try await pipeline.run(onProgress: { progress in
            progressEvents.append(progress)
        })

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
        let transcript = try await pipeline.run(onProgress: { progress in
            progressEvents.append(progress)
        })

        #expect(transcript.lines == ["First unique row", "Second unique row"])
        #expect(ocr.detectedFrameIndices == [0, 2])
        #expect(progressEvents.map(\.skippedFrames) == [0, 1, 1])
        #expect(progressEvents[1].scrollState == .paused)
    }

    @Test func smartPipelineCommitsReverseScrollFrames() async throws {
        let source = MockVideoSource(frameCount: 4)
        let ocr = MockOCRBackend(linesByFrame: [
            0: [Line(text: "Opening visible item", bbox: BBox(x: 0, y: 0, w: 80, h: 12), confidence: 1)],
            1: [Line(text: "Forward-only new item", bbox: BBox(x: 0, y: 0, w: 80, h: 12), confidence: 1)],
            2: [Line(text: "Reverse-scroll revealed item", bbox: BBox(x: 0, y: 0, w: 80, h: 12), confidence: 1)],
            3: [Line(text: "Forward again final item", bbox: BBox(x: 0, y: 0, w: 80, h: 12), confidence: 1)],
        ])
        let motion = MockMotionEstimator(dys: [1, -1, 1])
        let pipeline = Pipeline(
            video: source,
            ocr: ocr,
            motion: motion,
            config: PipelineConfig(
                fps: 1.0,
                schedulerConfig: SchedulerConfig(
                    pauseThresholdPx: 0.1,
                    fastThresholdRatio: 100,
                    discontinuityThresholdRatio: 100,
                    historySize: 1,
                    commitReverse: true
                ),
                adaptive: true
            )
        )

        var progressEvents: [PipelineProgress] = []
        let transcript = try await pipeline.run(onProgress: { progress in
            progressEvents.append(progress)
        })

        #expect(progressEvents.compactMap(\.scrollState).contains(.reverse))
        #expect(transcript.lines.contains("Reverse-scroll revealed item"))
        #expect(transcript.lines.contains("Forward again final item"))
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

    @Test func blankVideoPipelineCompletesWithZeroLines() async throws {
        let source = MockVideoSource(frameCount: 3)
        let ocr = MockOCRBackend(linesByFrame: [
            0: [],
            1: [],
            2: [],
        ])
        let pipeline = Pipeline(video: source, ocr: ocr, config: PipelineConfig(fps: 1.0))

        var progressEvents: [PipelineProgress] = []
        let transcript = try await pipeline.run(onProgress: { progress in
            progressEvents.append(progress)
        })

        #expect(transcript.lines.isEmpty)
        #expect(progressEvents.last?.processedFrames == 3)
        #expect(progressEvents.last?.recognizedLines == 0)
        #expect(progressEvents.last?.fractionCompleted == 1)
    }

    @Test func fourMinuteEquivalentPipelineCompletesWithoutFrameAccumulation() async throws {
        let frameCount = 480
        let fps = 2.0
        // 480 frames at 2 fps == a 240s (4-minute) clip, so expectedFrames lines
        // up with the number of frames the mock actually yields.
        let source = MockVideoSource(frameCount: frameCount, durationSeconds: Double(frameCount) / fps)
        let ocr = SequentialOCRBackend()
        let pipeline = Pipeline(
            video: source,
            ocr: ocr,
            config: PipelineConfig(fps: fps)
        )

        var lastProgress: PipelineProgress?
        let transcript = try await pipeline.run(onProgress: { progress in
            lastProgress = progress
        })

        #expect(transcript.lines.count == frameCount)
        #expect(lastProgress?.processedFrames == frameCount)
        #expect(lastProgress?.fractionCompleted == 1)
    }

    @Test func nonAdaptivePipelineRunsOCRWithBoundedConcurrency() async throws {
        let source = MockVideoSource(frameCount: 6)
        let ocr = ConcurrencyTrackingOCRBackend(delayNanoseconds: 20_000_000)
        let pipeline = Pipeline(
            video: source,
            ocr: ocr,
            config: PipelineConfig(fps: 1.0, ocrConcurrency: 3)
        )

        let transcript = try await pipeline.run()

        #expect(transcript.lines.count == 6)
        #expect(ocr.maxInFlight > 1)
        #expect(ocr.maxInFlight <= 3)
    }

    @Test func coverageRefinementBackfillsRiskyIntervals() async throws {
        let source = TimedMockVideoSource(durationSeconds: 2)
        let ocr = TimestampOCRBackend()
        let pipeline = Pipeline(
            video: source,
            ocr: ocr,
            config: PipelineConfig(
                fps: 1.0,
                ocrConcurrency: 2,
                coverageRefinement: CoverageRefinementConfig(
                    refinementFPS: 4,
                    intervalPaddingSeconds: 0,
                    lineDropMinimumDelta: 2
                )
            )
        )

        let transcript = try await pipeline.run()

        #expect(transcript.lines.contains("Middle important detail"))
        #expect(ocr.detectedTimestamps.contains { abs($0 - 0.25) < 0.01 || abs($0 - 0.5) < 0.01 })
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

    @Test func pipelineResumeUsesCheckpointedSamplesWithoutRedoingOCR() async throws {
        let source = TimedMockVideoSource(durationSeconds: 3)
        let ocr = TimestampTextOCRBackend()
        let savedLine = Line(
            text: "Saved first frame",
            bbox: BBox(x: 0, y: 0, w: 80, h: 12),
            confidence: 1
        )
        let resumeState = PipelineResumeState(
            baseSamples: [
                PipelineFrameCheckpoint(
                    idx: 0,
                    timestamp: 0,
                    frameHeight: 100,
                    lines: [PipelineLineCheckpoint(line: savedLine)],
                    didOCR: true,
                    averageConfidence: 1,
                    coverageMinY: 0,
                    coverageMaxY: 0.12,
                    coverageAreaRatio: 0.1,
                    dy: nil,
                    scrollStateRawValue: nil,
                    shouldAppendNew: true
                ),
            ],
            startSeconds: 1
        )
        let pipeline = Pipeline(video: source, ocr: ocr, config: PipelineConfig(fps: 1.0))

        let transcript = try await pipeline.run(resumeState: resumeState)

        #expect(
            transcript.lines == [
                "Saved first frame",
                distinctSubtitleText(forFrame: 1_000),
                distinctSubtitleText(forFrame: 2_000),
            ]
        )
        #expect(await ocr.detectedTimestamps() == [1, 2])
    }
}

private final class MockVideoSource: VideoSource {
    let sourceURL = URL(fileURLWithPath: "/tmp/mock.mov")
    private let frameCount: Int
    private let duration: Double
    private let image: CGImage

    /// `durationSeconds` defaults to `Double(frameCount)` (matching a 1 fps clip);
    /// pass it explicitly when the test runs at a different FPS so that
    /// `expectedFrames` (= ceil(duration * fps)) lines up with the yielded frames.
    init(frameCount: Int, durationSeconds: Double? = nil) {
        self.frameCount = frameCount
        self.duration = durationSeconds ?? Double(frameCount)
        self.image = makeOnePixelImage()
    }

    func durationSeconds() async throws -> Double {
        duration
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
    private let lock = NSLock()
    private var _detectedFrameIndices: [Int] = []

    /// Thread-safe: the concurrent `runFixed` path calls `detect` from several
    /// task-group children at once, so the backing array needs synchronization.
    var detectedFrameIndices: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return _detectedFrameIndices
    }

    init(linesByFrame: [Int: [Line]]) {
        self.linesByFrame = linesByFrame
    }

    func detect(in frame: VideoFrame) async throws -> [Line] {
        lock.lock()
        _detectedFrameIndices.append(frame.idx)
        lock.unlock()
        return linesByFrame[frame.idx] ?? []
    }
}

private final class TimestampOCRBackend: OCRBackend {
    private let lock = NSLock()
    private var timestamps: [Double] = []

    var detectedTimestamps: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return timestamps
    }

    func detect(in frame: VideoFrame) async throws -> [Line] {
        lock.lock()
        timestamps.append(frame.timestamp)
        lock.unlock()

        if abs(frame.timestamp) < 0.01 {
            return [
                Line(text: "Alpha row", bbox: BBox(x: 0, y: 0, w: 80, h: 10), confidence: 1),
                Line(text: "Beta row", bbox: BBox(x: 0, y: 12, w: 80, h: 10), confidence: 1),
                Line(text: "Gamma row", bbox: BBox(x: 0, y: 24, w: 80, h: 10), confidence: 1),
                Line(text: "Delta row", bbox: BBox(x: 0, y: 36, w: 80, h: 10), confidence: 1),
            ]
        }
        if abs(frame.timestamp - 1.0) < 0.01 {
            return [
                Line(text: "Omega row", bbox: BBox(x: 0, y: 0, w: 80, h: 10), confidence: 1),
            ]
        }
        return [
            Line(text: "Middle important detail", bbox: BBox(x: 0, y: 18, w: 80, h: 10), confidence: 1),
        ]
    }
}

private final class TimestampTextOCRBackend: OCRBackend {
    private let recorder = TimestampRecorder()

    func detectedTimestamps() async -> [Double] {
        await recorder.values
    }

    func detect(in frame: VideoFrame) async throws -> [Line] {
        await recorder.append(frame.timestamp)

        return [
            Line(
                text: distinctSubtitleText(forFrame: Int(frame.timestamp * 1000)),
                bbox: BBox(x: 0, y: 0, w: 80, h: 12),
                confidence: 1
            ),
        ]
    }
}

private actor TimestampRecorder {
    private var timestamps: [Double] = []

    var values: [Double] { timestamps }

    func append(_ timestamp: Double) {
        timestamps.append(timestamp)
    }
}

private final class SequentialOCRBackend: OCRBackend {
    func detect(in frame: VideoFrame) async throws -> [Line] {
        [
            Line(
                text: distinctSubtitleText(forFrame: frame.idx),
                bbox: BBox(x: 0, y: 0, w: 80, h: 12),
                confidence: 1
            ),
        ]
    }
}

/// Deterministic, high-entropy text that is mutually dissimilar between frames.
///
/// Real scrolling subtitles are distinct sentences; a label like
/// "Unique frame 0" vs "Unique frame 1" is ~92% fuzzy-similar and would be
/// collapsed by the Stitcher's 80% dedup threshold. This hashes the frame index
/// (splitmix64) into a 20-char base-36 string so consecutive frames stay well
/// below that threshold while remaining reproducible.
private func distinctSubtitleText(forFrame idx: Int) -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    var z = UInt64(bitPattern: Int64(idx)) &+ 0x9E37_79B9_7F4A_7C15
    var out = ""
    for _ in 0..<20 {
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        out.append(alphabet[Int(z % UInt64(alphabet.count))])
        z = z &+ 0x9E37_79B9_7F4A_7C15
    }
    return out
}

private final class TimedMockVideoSource: VideoSource {
    let sourceURL = URL(fileURLWithPath: "/tmp/timed-mock.mov")
    private let duration: Double
    private let image: CGImage

    init(durationSeconds: Double) {
        self.duration = durationSeconds
        self.image = makeOnePixelImage()
    }

    func durationSeconds() async throws -> Double {
        duration
    }

    func frames(targetFPS: Double) -> AsyncThrowingStream<VideoFrame, Error> {
        frames(targetFPS: targetFPS, startSeconds: 0, endSeconds: nil)
    }

    func frames(
        targetFPS: Double,
        startSeconds: Double,
        endSeconds: Double?
    ) -> AsyncThrowingStream<VideoFrame, Error> {
        AsyncThrowingStream { continuation in
            let start = max(0, startSeconds)
            let end = min(endSeconds ?? duration, duration)
            guard targetFPS > 0, end > start else {
                continuation.finish()
                return
            }

            let count = max(1, Int(ceil((end - start) * targetFPS)))
            for offset in 0..<count {
                let timestamp = start + Double(offset) / targetFPS
                guard timestamp <= end else { break }
                continuation.yield(
                    VideoFrame(
                        idx: Int((timestamp * 1000).rounded(.toNearestOrAwayFromZero)),
                        timestamp: timestamp,
                        image: image
                    )
                )
            }
            continuation.finish()
        }
    }
}

private final class ConcurrencyTrackingOCRBackend: OCRBackend {
    private let delayNanoseconds: UInt64
    private let lock = NSLock()
    private var inFlight = 0
    private var peakInFlight = 0

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    var maxInFlight: Int {
        lock.lock()
        defer { lock.unlock() }
        return peakInFlight
    }

    func detect(in frame: VideoFrame) async throws -> [Line] {
        lock.lock()
        inFlight += 1
        peakInFlight = max(peakInFlight, inFlight)
        lock.unlock()

        try await Task.sleep(nanoseconds: delayNanoseconds)

        lock.lock()
        inFlight -= 1
        lock.unlock()

        return [
            Line(
                text: distinctSubtitleText(forFrame: frame.idx),
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
