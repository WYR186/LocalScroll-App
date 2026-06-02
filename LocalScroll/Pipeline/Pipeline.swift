import Foundation
import LocalScrollCore

public enum StitchMode: String, CaseIterable, Identifiable, Sendable {
    case scroll
    case caption

    public var id: String { rawValue }
}

public struct PipelineConfig: Sendable {
    public var fps: Double
    public var stitchConfig: StitchConfig
    public var schedulerConfig: SchedulerConfig
    public var adaptive: Bool
    public var stitchMode: StitchMode
    public var incrementalThreshold: Int

    public init(
        fps: Double = 2.0,
        stitchConfig: StitchConfig = StitchConfig(),
        schedulerConfig: SchedulerConfig = SchedulerConfig(),
        adaptive: Bool = false,
        stitchMode: StitchMode = .scroll,
        incrementalThreshold: Int = 82
    ) {
        self.fps = fps
        self.stitchConfig = stitchConfig
        self.schedulerConfig = schedulerConfig
        self.adaptive = adaptive
        self.stitchMode = stitchMode
        self.incrementalThreshold = incrementalThreshold
    }
}

public struct PipelineProgress: Equatable, Sendable {
    public let processedFrames: Int
    public let skippedFrames: Int
    public let expectedFrames: Int
    public let timestamp: Double
    public let recognizedLines: Int
    public let scrollState: ScrollState?

    public var fractionCompleted: Double {
        guard expectedFrames > 0 else { return 0 }
        return min(1, Double(processedFrames) / Double(expectedFrames))
    }
}

public final class Pipeline {
    private let video: VideoSource
    private let ocr: OCRBackend
    private let motion: MotionEstimator?
    private let preprocessor: FramePreprocessor?
    private let config: PipelineConfig

    public init(
        video: VideoSource,
        ocr: OCRBackend,
        motion: MotionEstimator? = nil,
        preprocessor: FramePreprocessor? = nil,
        config: PipelineConfig = PipelineConfig()
    ) {
        self.video = video
        self.ocr = ocr
        self.motion = motion
        self.preprocessor = preprocessor
        self.config = config
    }

    /// Run extraction: fixed-FPS frames, optional adaptive sampling, Vision OCR, Stitcher dedup.
    public func run(
        onProgress: ((PipelineProgress) async -> Void)? = nil
    ) async throws -> Transcript {
        let duration = try await video.durationSeconds()
        let expectedFrames = max(1, Int(ceil(duration * config.fps)))
        var stitcher = Stitcher(config: config.stitchConfig)
        var scheduler = Scheduler(config.schedulerConfig)
        var previousFrame: VideoFrame?
        let shouldEstimateMotion = config.adaptive && motion != nil
        var processedFrames = 0
        var skippedFrames = 0

        for try await frame in video.frames(targetFPS: config.fps) {
            try Task.checkCancellation()

            var decision: FrameDecision?
            if config.adaptive, let motion, let previous = previousFrame {
                let dy = try await motion.estimateDy(previous: previous, current: frame)
                try Task.checkCancellation()
                decision = scheduler.decide(dy: dy, frameHeightPx: frame.height)

                if decision?.shouldOcr == false {
                    processedFrames += 1
                    skippedFrames += 1
                    await onProgress?(
                        PipelineProgress(
                            processedFrames: processedFrames,
                            skippedFrames: skippedFrames,
                            expectedFrames: expectedFrames,
                            timestamp: frame.timestamp,
                            recognizedLines: 0,
                            scrollState: decision?.state
                        )
                    )
                    previousFrame = shouldEstimateMotion ? frame : nil
                    continue
                }
            }

            let ocrFrame: VideoFrame
            if let preprocessor {
                ocrFrame = try await preprocessor.process(frame)
                try Task.checkCancellation()
            } else {
                ocrFrame = frame
            }

            let lines = try await ocr.detect(in: ocrFrame)
            try Task.checkCancellation()
            if let decision, !decision.shouldAppendNew {
                stitcher.consumeReverse(lines, frameIdx: frame.idx, timestamp: frame.timestamp)
            } else {
                stitcher.consume(lines, frameIdx: frame.idx, timestamp: frame.timestamp)
            }

            processedFrames += 1
            await onProgress?(
                PipelineProgress(
                    processedFrames: processedFrames,
                    skippedFrames: skippedFrames,
                    expectedFrames: expectedFrames,
                    timestamp: frame.timestamp,
                    recognizedLines: lines.count,
                    scrollState: decision?.state
                )
            )
            previousFrame = shouldEstimateMotion ? frame : nil
        }

        var transcript = stitcher.finalize()
        transcript.sourceVideo = video.sourceURL
        if config.stitchMode == .caption {
            transcript.lines = collapseIncrementalLines(
                transcript.lines,
                threshold: config.incrementalThreshold
            )
        }
        return transcript
    }
}
