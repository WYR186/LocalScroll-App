import Foundation
import LocalScrollCore

public enum StitchMode: String, CaseIterable, Identifiable, Sendable {
    case scroll
    case caption

    public var id: String { rawValue }
}

public struct CoverageRefinementConfig: Sendable {
    public var refinementFPS: Double
    public var intervalPaddingSeconds: Double
    public var maxRiskIntervals: Int
    public var largeDyFrameRatio: Double
    public var minimumVerticalCoverageOverlap: Double
    public var minimumTextOverlapRatio: Double
    public var lineDropRatio: Double
    public var lineDropMinimumDelta: Int
    public var lowConfidenceThreshold: Double
    public var minimumLinesForOverlapCheck: Int

    public init(
        refinementFPS: Double = 8.0,
        intervalPaddingSeconds: Double = 0.15,
        maxRiskIntervals: Int = 40,
        largeDyFrameRatio: Double = 0.55,
        minimumVerticalCoverageOverlap: Double = 0.25,
        minimumTextOverlapRatio: Double = 0.2,
        lineDropRatio: Double = 0.55,
        lineDropMinimumDelta: Int = 3,
        lowConfidenceThreshold: Double = 0.55,
        minimumLinesForOverlapCheck: Int = 3
    ) {
        self.refinementFPS = max(1, refinementFPS)
        self.intervalPaddingSeconds = max(0, intervalPaddingSeconds)
        self.maxRiskIntervals = max(1, maxRiskIntervals)
        self.largeDyFrameRatio = largeDyFrameRatio
        self.minimumVerticalCoverageOverlap = minimumVerticalCoverageOverlap
        self.minimumTextOverlapRatio = minimumTextOverlapRatio
        self.lineDropRatio = lineDropRatio
        self.lineDropMinimumDelta = max(1, lineDropMinimumDelta)
        self.lowConfidenceThreshold = lowConfidenceThreshold
        self.minimumLinesForOverlapCheck = max(1, minimumLinesForOverlapCheck)
    }
}

public struct PipelineConfig: Sendable {
    public var fps: Double
    public var stitchConfig: StitchConfig
    public var schedulerConfig: SchedulerConfig
    public var adaptive: Bool
    public var stitchMode: StitchMode
    public var incrementalThreshold: Int
    public var ocrConcurrency: Int
    public var coverageRefinement: CoverageRefinementConfig?

    public init(
        fps: Double = 2.0,
        stitchConfig: StitchConfig = StitchConfig(),
        schedulerConfig: SchedulerConfig = SchedulerConfig(),
        adaptive: Bool = false,
        stitchMode: StitchMode = .scroll,
        incrementalThreshold: Int = 82,
        ocrConcurrency: Int = 3,
        coverageRefinement: CoverageRefinementConfig? = nil
    ) {
        self.fps = fps
        self.stitchConfig = stitchConfig
        self.schedulerConfig = schedulerConfig
        self.adaptive = adaptive
        self.stitchMode = stitchMode
        self.incrementalThreshold = incrementalThreshold
        self.ocrConcurrency = max(1, ocrConcurrency)
        self.coverageRefinement = coverageRefinement
    }
}

public struct PipelineLineCheckpoint: Codable, Equatable, Sendable {
    public var text: String
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int
    public var confidence: Double

    public init(line: Line) {
        self.text = line.text
        self.x = line.bbox.x
        self.y = line.bbox.y
        self.w = line.bbox.w
        self.h = line.bbox.h
        self.confidence = line.confidence
    }

    public var line: Line {
        Line(
            text: text,
            bbox: BBox(x: x, y: y, w: w, h: h),
            confidence: confidence
        )
    }
}

public struct PipelineFrameCheckpoint: Codable, Equatable, Sendable {
    public var idx: Int
    public var timestamp: Double
    public var frameHeight: Int
    public var lines: [PipelineLineCheckpoint]
    public var didOCR: Bool
    public var averageConfidence: Double?
    public var coverageMinY: Double?
    public var coverageMaxY: Double?
    public var coverageAreaRatio: Double?
    public var dy: Double?
    public var scrollStateRawValue: String?
    public var shouldAppendNew: Bool
}

public struct PipelineResumeState: Equatable, Sendable {
    public var baseSamples: [PipelineFrameCheckpoint]
    public var startSeconds: Double

    public init(baseSamples: [PipelineFrameCheckpoint], startSeconds: Double) {
        self.baseSamples = baseSamples
        self.startSeconds = max(0, startSeconds)
    }
}

public struct PipelineCheckpointSnapshot: Equatable, Sendable {
    public var timestamp: Double
    public var processedFrames: Int
    public var baseSamples: [PipelineFrameCheckpoint]
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
        resumeState: PipelineResumeState? = nil,
        checkpointEveryFrames: Int = 12,
        onCheckpoint: ((PipelineCheckpointSnapshot) async -> Void)? = nil,
        onProgress: ((PipelineProgress) async -> Void)? = nil
    ) async throws -> Transcript {
        if let coverageRefinement = config.coverageRefinement {
            return try await runCoverageRefined(
                coverageRefinement,
                resumeState: resumeState,
                checkpointEveryFrames: checkpointEveryFrames,
                onCheckpoint: onCheckpoint,
                onProgress: onProgress
            )
        }
        if resumeState != nil || onCheckpoint != nil {
            return try await runCheckpointed(
                resumeState: resumeState,
                checkpointEveryFrames: checkpointEveryFrames,
                onCheckpoint: onCheckpoint,
                onProgress: onProgress
            )
        }
        if config.adaptive, motion != nil {
            return try await runAdaptive(onProgress: onProgress)
        }
        return try await runFixed(onProgress: onProgress)
    }

    private func runCoverageRefined(
        _ refinement: CoverageRefinementConfig,
        resumeState: PipelineResumeState?,
        checkpointEveryFrames: Int,
        onCheckpoint: ((PipelineCheckpointSnapshot) async -> Void)?,
        onProgress: ((PipelineProgress) async -> Void)?
    ) async throws -> Transcript {
        let duration = try await video.durationSeconds()
        let expectedBaseFrames = max(1, Int(ceil(duration * config.fps)))
        var baseSamples = resumeState?.baseSamples.map(FrameOCRSample.init(checkpoint:)) ?? []
        let resumeStart = resumeState?.startSeconds ?? 0

        if config.adaptive, motion != nil {
            let collected = try await collectAdaptiveBaseSamples(
                startSeconds: resumeStart,
                initialSamples: baseSamples,
                expectedFrames: expectedBaseFrames,
                checkpointEveryFrames: checkpointEveryFrames,
                onCheckpoint: onCheckpoint,
                onProgress: onProgress
            )
            baseSamples = collected
        } else {
            let collection = try await collectFixedSamples(
                stream: video.frames(
                    targetFPS: config.fps,
                    startSeconds: resumeStart,
                    endSeconds: nil
                ),
                expectedFrames: expectedBaseFrames,
                processedOffset: baseSamples.count,
                skippedFrames: 0,
                initialSamples: baseSamples,
                checkpointEveryFrames: checkpointEveryFrames,
                onCheckpoint: onCheckpoint,
                onProgress: onProgress
            )
            baseSamples = collection.samples
        }

        let intervals = riskIntervals(
            from: baseSamples,
            duration: duration,
            refinement: refinement
        )

        guard !intervals.isEmpty else {
            return stitch(samples: baseSamples)
        }

        let refinementExpectedFrames = intervals.reduce(0) { total, interval in
            total + max(1, Int(ceil((interval.end - interval.start) * refinement.refinementFPS)))
        }
        let totalExpectedFrames = expectedBaseFrames + refinementExpectedFrames
        var supplementalSamples: [FrameOCRSample] = []
        supplementalSamples.reserveCapacity(refinementExpectedFrames)
        var processedSupplemental = 0

        for interval in intervals {
            try Task.checkCancellation()
            let collection = try await collectFixedSamples(
                stream: video.frames(
                    targetFPS: refinement.refinementFPS,
                    startSeconds: interval.start,
                    endSeconds: interval.end
                ),
                expectedFrames: totalExpectedFrames,
                processedOffset: expectedBaseFrames + processedSupplemental,
                skippedFrames: 0,
                initialSamples: [],
                checkpointEveryFrames: 0,
                onCheckpoint: nil,
                onProgress: onProgress
            )
            supplementalSamples.append(contentsOf: collection.samples)
            processedSupplemental += collection.processedFrames
        }

        return stitch(samples: mergedSamples(baseSamples + supplementalSamples))
    }

    private func collectAdaptiveBaseSamples(
        startSeconds: Double,
        initialSamples: [FrameOCRSample],
        expectedFrames: Int,
        checkpointEveryFrames: Int,
        onCheckpoint: ((PipelineCheckpointSnapshot) async -> Void)?,
        onProgress: ((PipelineProgress) async -> Void)?
    ) async throws -> [FrameOCRSample] {
        var scheduler = Scheduler(config.schedulerConfig)
        var previousFrame: VideoFrame?
        var samples = initialSamples
        var processedFrames = initialSamples.count
        var skippedFrames = 0

        for try await frame in video.frames(
            targetFPS: config.fps,
            startSeconds: startSeconds,
            endSeconds: nil
        ) {
            try Task.checkCancellation()

            var dy: Double?
            var decision: FrameDecision?
            if let motion, let previous = previousFrame {
                let estimatedDy = try await motion.estimateDy(previous: previous, current: frame)
                try Task.checkCancellation()
                dy = estimatedDy
                decision = scheduler.decide(dy: estimatedDy, frameHeightPx: frame.height)

                if decision?.shouldOcr == false {
                    processedFrames += 1
                    skippedFrames += 1
                    samples.append(
                        FrameOCRSample(
                            idx: frame.idx,
                            timestamp: frame.timestamp,
                            frameHeight: frame.height,
                            lines: [],
                            didOCR: false,
                            averageConfidence: nil,
                            coverage: nil,
                            dy: dy,
                            scrollState: decision?.state,
                            shouldAppendNew: false
                        )
                    )
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
                    await checkpointIfNeeded(
                        samples: samples,
                        processedFrames: processedFrames,
                        checkpointEveryFrames: checkpointEveryFrames,
                        onCheckpoint: onCheckpoint
                    )
                    previousFrame = frame
                    continue
                }
            }

            let result = try await recognize(frame)
            let sample = makeSample(
                from: result,
                dy: dy,
                scrollState: decision?.state,
                shouldAppendNew: decision?.shouldAppendNew ?? true
            )
            samples.append(sample)

            processedFrames += 1
            await onProgress?(
                PipelineProgress(
                    processedFrames: processedFrames,
                    skippedFrames: skippedFrames,
                    expectedFrames: expectedFrames,
                    timestamp: frame.timestamp,
                    recognizedLines: result.lines.count,
                    scrollState: decision?.state
                )
            )
            await checkpointIfNeeded(
                samples: samples,
                processedFrames: processedFrames,
                checkpointEveryFrames: checkpointEveryFrames,
                onCheckpoint: onCheckpoint
            )
            previousFrame = frame
        }

        return samples
    }

    private struct SampleCollection {
        let samples: [FrameOCRSample]
        let processedFrames: Int
    }

    private func collectFixedSamples(
        stream: AsyncThrowingStream<VideoFrame, Error>,
        expectedFrames: Int,
        processedOffset: Int,
        skippedFrames: Int,
        initialSamples: [FrameOCRSample] = [],
        checkpointEveryFrames: Int = 0,
        onCheckpoint: ((PipelineCheckpointSnapshot) async -> Void)? = nil,
        onProgress: ((PipelineProgress) async -> Void)?
    ) async throws -> SampleCollection {
        var samples = initialSamples
        var processedFrames = 0

        try await runConcurrentOCR(
            stream: stream,
            maxConcurrency: config.ocrConcurrency
        ) { result in
            let sample = makeSample(
                from: result,
                dy: nil,
                scrollState: nil,
                shouldAppendNew: true
            )
            samples.append(sample)
            processedFrames += 1
            await onProgress?(
                PipelineProgress(
                    processedFrames: processedOffset + processedFrames,
                    skippedFrames: skippedFrames,
                    expectedFrames: expectedFrames,
                    timestamp: result.frame.timestamp,
                    recognizedLines: result.lines.count,
                    scrollState: nil
                )
            )
            await checkpointIfNeeded(
                samples: samples,
                processedFrames: processedOffset + processedFrames,
                checkpointEveryFrames: checkpointEveryFrames,
                onCheckpoint: onCheckpoint
            )
        }

        return SampleCollection(samples: samples, processedFrames: processedFrames)
    }

    private func runCheckpointed(
        resumeState: PipelineResumeState?,
        checkpointEveryFrames: Int,
        onCheckpoint: ((PipelineCheckpointSnapshot) async -> Void)?,
        onProgress: ((PipelineProgress) async -> Void)?
    ) async throws -> Transcript {
        let duration = try await video.durationSeconds()
        let expectedFrames = max(1, Int(ceil(duration * config.fps)))
        let initialSamples = resumeState?.baseSamples.map(FrameOCRSample.init(checkpoint:)) ?? []
        let startSeconds = resumeState?.startSeconds ?? 0

        let samples: [FrameOCRSample]
        if config.adaptive, motion != nil {
            samples = try await collectAdaptiveBaseSamples(
                startSeconds: startSeconds,
                initialSamples: initialSamples,
                expectedFrames: expectedFrames,
                checkpointEveryFrames: checkpointEveryFrames,
                onCheckpoint: onCheckpoint,
                onProgress: onProgress
            )
        } else {
            samples = try await collectFixedSamples(
                stream: video.frames(
                    targetFPS: config.fps,
                    startSeconds: startSeconds,
                    endSeconds: nil
                ),
                expectedFrames: expectedFrames,
                processedOffset: initialSamples.count,
                skippedFrames: 0,
                initialSamples: initialSamples,
                checkpointEveryFrames: checkpointEveryFrames,
                onCheckpoint: onCheckpoint,
                onProgress: onProgress
            ).samples
        }

        return stitch(samples: samples)
    }

    private func runFixed(
        onProgress: ((PipelineProgress) async -> Void)?
    ) async throws -> Transcript {
        let duration = try await video.durationSeconds()
        let expectedFrames = max(1, Int(ceil(duration * config.fps)))
        var stitcher = Stitcher(config: config.stitchConfig)
        var processedFrames = 0

        try await runConcurrentOCR(
            stream: video.frames(targetFPS: config.fps),
            maxConcurrency: config.ocrConcurrency
        ) { result in
            stitcher.consume(
                result.lines,
                frameIdx: result.frame.idx,
                timestamp: result.frame.timestamp
            )
            processedFrames += 1
            await onProgress?(
                PipelineProgress(
                    processedFrames: processedFrames,
                    skippedFrames: 0,
                    expectedFrames: expectedFrames,
                    timestamp: result.frame.timestamp,
                    recognizedLines: result.lines.count,
                    scrollState: nil
                )
            )
        }

        return finalize(stitcher)
    }

    private func runAdaptive(
        onProgress: ((PipelineProgress) async -> Void)?
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

        return finalize(stitcher)
    }

    private struct OCRFrameResult {
        let frame: VideoFrame
        let ocrWidth: Int
        let ocrHeight: Int
        let lines: [Line]
    }

    private struct FrameOCRSample {
        let idx: Int
        let timestamp: Double
        let frameHeight: Int
        let lines: [Line]
        let didOCR: Bool
        let averageConfidence: Double?
        let coverage: BBoxCoverage?
        let dy: Double?
        let scrollState: ScrollState?
        let shouldAppendNew: Bool

        init(
            idx: Int,
            timestamp: Double,
            frameHeight: Int,
            lines: [Line],
            didOCR: Bool,
            averageConfidence: Double?,
            coverage: BBoxCoverage?,
            dy: Double?,
            scrollState: ScrollState?,
            shouldAppendNew: Bool
        ) {
            self.idx = idx
            self.timestamp = timestamp
            self.frameHeight = frameHeight
            self.lines = lines
            self.didOCR = didOCR
            self.averageConfidence = averageConfidence
            self.coverage = coverage
            self.dy = dy
            self.scrollState = scrollState
            self.shouldAppendNew = shouldAppendNew
        }

        init(checkpoint: PipelineFrameCheckpoint) {
            let coverage: BBoxCoverage?
            if let minY = checkpoint.coverageMinY,
               let maxY = checkpoint.coverageMaxY,
               let areaRatio = checkpoint.coverageAreaRatio {
                coverage = BBoxCoverage(minY: minY, maxY: maxY, areaRatio: areaRatio)
            } else {
                coverage = nil
            }
            self.init(
                idx: checkpoint.idx,
                timestamp: checkpoint.timestamp,
                frameHeight: checkpoint.frameHeight,
                lines: checkpoint.lines.map(\.line),
                didOCR: checkpoint.didOCR,
                averageConfidence: checkpoint.averageConfidence,
                coverage: coverage,
                dy: checkpoint.dy,
                scrollState: checkpoint.scrollStateRawValue.flatMap(ScrollState.init(rawValue:)),
                shouldAppendNew: checkpoint.shouldAppendNew
            )
        }

        var checkpoint: PipelineFrameCheckpoint {
            PipelineFrameCheckpoint(
                idx: idx,
                timestamp: timestamp,
                frameHeight: frameHeight,
                lines: lines.map(PipelineLineCheckpoint.init(line:)),
                didOCR: didOCR,
                averageConfidence: averageConfidence,
                coverageMinY: coverage?.minY,
                coverageMaxY: coverage?.maxY,
                coverageAreaRatio: coverage?.areaRatio,
                dy: dy,
                scrollStateRawValue: scrollState?.rawValue,
                shouldAppendNew: shouldAppendNew
            )
        }
    }

    private struct BBoxCoverage {
        let minY: Double
        let maxY: Double
        let areaRatio: Double

        var span: Double {
            max(0, maxY - minY)
        }
    }

    private struct RiskInterval {
        let start: Double
        let end: Double
    }

    private func recognize(_ frame: VideoFrame) async throws -> OCRFrameResult {
        let ocrFrame: VideoFrame
        if let preprocessor {
            ocrFrame = try await preprocessor.process(frame)
            try Task.checkCancellation()
        } else {
            ocrFrame = frame
        }

        let lines = try await ocr.detect(in: ocrFrame)
        try Task.checkCancellation()
        return OCRFrameResult(
            frame: frame,
            ocrWidth: ocrFrame.width,
            ocrHeight: ocrFrame.height,
            lines: lines
        )
    }

    /// Run OCR over a frame stream with bounded concurrency, delivering results
    /// to `onResult` in the stream's original (ascending) order.
    ///
    /// Unlike a fixed batch, this keeps up to `maxConcurrency` OCR tasks in
    /// flight continuously: as soon as one finishes it pulls and starts the next
    /// decoded frame, so decoding overlaps OCR instead of stalling at every batch
    /// boundary. A small reorder buffer restores frame order before stitching.
    private func runConcurrentOCR(
        stream: AsyncThrowingStream<VideoFrame, Error>,
        maxConcurrency: Int,
        onResult: (OCRFrameResult) async throws -> Void
    ) async throws {
        let concurrency = max(1, maxConcurrency)
        try await withThrowingTaskGroup(of: (Int, OCRFrameResult).self) { group in
            var iterator = stream.makeAsyncIterator()
            var pullSeq = 0
            var nextToEmit = 0
            var inFlight = 0
            var exhausted = false
            var pending: [Int: OCRFrameResult] = [:]

            while true {
                while inFlight < concurrency, !exhausted {
                    try Task.checkCancellation()
                    if let frame = try await iterator.next() {
                        let seq = pullSeq
                        pullSeq += 1
                        inFlight += 1
                        group.addTask { [self] in
                            (seq, try await recognize(frame))
                        }
                    } else {
                        exhausted = true
                    }
                }

                guard inFlight > 0 else { break }

                guard let (seq, result) = try await group.next() else { break }
                inFlight -= 1
                pending[seq] = result
                while let ready = pending.removeValue(forKey: nextToEmit) {
                    try await onResult(ready)
                    nextToEmit += 1
                }
            }
        }
    }

    private func makeSample(
        from result: OCRFrameResult,
        dy: Double?,
        scrollState: ScrollState?,
        shouldAppendNew: Bool
    ) -> FrameOCRSample {
        FrameOCRSample(
            idx: result.frame.idx,
            timestamp: result.frame.timestamp,
            frameHeight: result.frame.height,
            lines: result.lines,
            didOCR: true,
            averageConfidence: averageConfidence(result.lines),
            coverage: bboxCoverage(
                result.lines,
                imageWidth: result.ocrWidth,
                imageHeight: result.ocrHeight
            ),
            dy: dy,
            scrollState: scrollState,
            shouldAppendNew: shouldAppendNew
        )
    }

    private func averageConfidence(_ lines: [Line]) -> Double? {
        guard !lines.isEmpty else { return nil }
        return lines.reduce(0) { $0 + $1.confidence } / Double(lines.count)
    }

    private func bboxCoverage(
        _ lines: [Line],
        imageWidth: Int,
        imageHeight: Int
    ) -> BBoxCoverage? {
        guard imageWidth > 0, imageHeight > 0, !lines.isEmpty else { return nil }

        var minY = Double.greatestFiniteMagnitude
        var maxY = 0.0
        var area = 0.0
        for line in lines {
            let y0 = max(0, min(imageHeight, line.bbox.y))
            let y1 = max(0, min(imageHeight, line.bbox.y + line.bbox.h))
            let x0 = max(0, min(imageWidth, line.bbox.x))
            let x1 = max(0, min(imageWidth, line.bbox.x + line.bbox.w))
            guard y1 > y0, x1 > x0 else { continue }

            minY = min(minY, Double(y0) / Double(imageHeight))
            maxY = max(maxY, Double(y1) / Double(imageHeight))
            area += Double((x1 - x0) * (y1 - y0))
        }

        guard minY.isFinite, maxY > minY else { return nil }
        return BBoxCoverage(
            minY: minY,
            maxY: maxY,
            areaRatio: area / Double(imageWidth * imageHeight)
        )
    }

    private func riskIntervals(
        from samples: [FrameOCRSample],
        duration: Double,
        refinement: CoverageRefinementConfig
    ) -> [RiskInterval] {
        guard samples.count >= 2 else { return [] }

        var intervals: [RiskInterval] = []
        for pair in zip(samples, samples.dropFirst()) {
            let previous = pair.0
            let current = pair.1
            guard current.timestamp > previous.timestamp else { continue }

            if isRiskyTransition(
                previous: previous,
                current: current,
                refinement: refinement
            ) {
                intervals.append(
                    RiskInterval(
                        start: max(0, previous.timestamp - refinement.intervalPaddingSeconds),
                        end: min(duration, current.timestamp + refinement.intervalPaddingSeconds)
                    )
                )
            }
        }

        return mergedIntervals(intervals)
            .prefix(refinement.maxRiskIntervals)
            .map { $0 }
    }

    private func isRiskyTransition(
        previous: FrameOCRSample,
        current: FrameOCRSample,
        refinement: CoverageRefinementConfig
    ) -> Bool {
        if current.scrollState == .discontinuity {
            return true
        }

        if let dy = current.dy,
           abs(dy) >= refinement.largeDyFrameRatio * Double(max(1, current.frameHeight)) {
            return true
        }

        guard previous.didOCR, current.didOCR else {
            return false
        }

        if current.lines.count + refinement.lineDropMinimumDelta <= previous.lines.count,
           Double(current.lines.count) <= Double(previous.lines.count) * refinement.lineDropRatio {
            return true
        }

        if let averageConfidence = current.averageConfidence,
           !current.lines.isEmpty,
           averageConfidence < refinement.lowConfidenceThreshold {
            return true
        }

        if previous.lines.count >= refinement.minimumLinesForOverlapCheck,
           current.lines.count >= refinement.minimumLinesForOverlapCheck {
            if let previousCoverage = previous.coverage,
               let currentCoverage = current.coverage,
               verticalOverlap(previousCoverage, currentCoverage) < refinement.minimumVerticalCoverageOverlap {
                return true
            }

            if textOverlap(previous.lines, current.lines) < refinement.minimumTextOverlapRatio {
                return true
            }
        }

        return false
    }

    private func verticalOverlap(_ lhs: BBoxCoverage, _ rhs: BBoxCoverage) -> Double {
        let intersection = max(0, min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY))
        let denominator = max(0.000_001, min(lhs.span, rhs.span))
        return intersection / denominator
    }

    private func textOverlap(_ lhs: [Line], _ rhs: [Line]) -> Double {
        let lhsTexts = lhs.map(\.text)
        let rhsTexts = rhs.map(\.text)
        guard !lhsTexts.isEmpty, !rhsTexts.isEmpty else { return 0 }

        var matches = 0
        var used = Set<Int>()
        for left in lhsTexts {
            if let index = rhsTexts.indices.first(where: { index in
                !used.contains(index) && similar(left, rhsTexts[index], threshold: 85)
            }) {
                matches += 1
                used.insert(index)
            }
        }
        return Double(matches) / Double(min(lhsTexts.count, rhsTexts.count))
    }

    private func mergedIntervals(_ intervals: [RiskInterval]) -> [RiskInterval] {
        let sorted = intervals
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }

        var merged: [RiskInterval] = []
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current = RiskInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                merged.append(current)
                current = interval
            }
        }
        merged.append(current)
        return merged
    }

    private func mergedSamples(_ samples: [FrameOCRSample]) -> [FrameOCRSample] {
        let sorted = samples.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.idx < $1.idx
            }
            return $0.timestamp < $1.timestamp
        }
        let timestampTolerance = max(0.005, 0.25 / max(1, config.fps))
        var merged: [FrameOCRSample] = []
        for sample in sorted {
            if let last = merged.last,
               abs(last.timestamp - sample.timestamp) <= timestampTolerance,
               last.lines == sample.lines {
                continue
            }
            merged.append(sample)
        }
        return merged
    }

    private func stitch(samples: [FrameOCRSample]) -> Transcript {
        var stitcher = Stitcher(config: config.stitchConfig)
        for sample in samples where sample.didOCR {
            if sample.shouldAppendNew {
                stitcher.consume(sample.lines, frameIdx: sample.idx, timestamp: sample.timestamp)
            } else {
                stitcher.consumeReverse(sample.lines, frameIdx: sample.idx, timestamp: sample.timestamp)
            }
        }
        return finalize(stitcher)
    }

    private func checkpointIfNeeded(
        samples: [FrameOCRSample],
        processedFrames: Int,
        checkpointEveryFrames: Int,
        onCheckpoint: ((PipelineCheckpointSnapshot) async -> Void)?
    ) async {
        guard let onCheckpoint,
              checkpointEveryFrames > 0,
              processedFrames > 0,
              processedFrames % checkpointEveryFrames == 0,
              let latest = samples.last else {
            return
        }
        await onCheckpoint(
            PipelineCheckpointSnapshot(
                timestamp: latest.timestamp,
                processedFrames: processedFrames,
                baseSamples: samples.map(\.checkpoint)
            )
        )
    }

    private func finalize(_ stitcher: Stitcher) -> Transcript {
        var stitcher = stitcher
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
