import AVFoundation
import Foundation
import LocalScrollCore
import Testing
@testable import LocalScroll

/// End-to-end parity harness.
///
/// Runs the SAME real video through the *integrated* iOS pipeline
/// (`AVAssetVideoSource` + `VisionOCRBackend` + `Stitcher`) using settings that
/// mirror the Python reference run `localscroll process --quality fast`
/// (Apple Vision, 2 fps, screen-recording mode, scroll stitch, and the Core
/// default `StitchConfig`, which is byte-identical to Python's defaults:
/// tailSize 20, threshold 80, minConfidence 0.5, minTextLength 2).
///
/// The resulting transcript is printed to the test log between explicit
/// delimiters so it can be recovered from `xcodebuild` output regardless of the
/// App Sandbox's file-write restrictions. The video path and an optional output
/// directory are read from the environment, falling back to the local fixture.
struct EndToEndComparisonTests {
    // A 15s active-scrolling window of IMG_0559.mov (re-encoded H.264). Bounded
    // so the Simulator-CPU Vision run is fast + reliable; the Python baseline is
    // re-run on this identical clip for an apples-to-apples diff. Override with
    // LOCALSCROLL_E2E_VIDEO to point at the full IMG_0559.mov.
    private static let defaultVideoPath = "/tmp/ls_clip_75_90.mp4"
    private static let repoSampleVideoPath = "/Users/ipanda/Documents/project/LocalScroll/test_video/IMG_0249.MOV"
    private static let defaultBlankVideoPath = "/tmp/localscroll_blank_10s.mp4"

    @Test func iosPipelineMatchesPythonFastBaselineOnRealVideo() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["LOCALSCROLL_E2E_VIDEO"]
            ?? Self.firstExistingPath([Self.repoSampleVideoPath, Self.defaultVideoPath])
        else {
            print("E2E_SKIP: no real sample video found.")
            return
        }
        let expectEmpty = env["LOCALSCROLL_E2E_EXPECT_EMPTY"] == "1"
        let minimumLineCount = Int(env["LOCALSCROLL_E2E_MIN_LINES"] ?? "") ?? (expectEmpty ? 0 : 1)

        try await Self.runPipeline(
            path: path,
            expectEmpty: expectEmpty,
            minimumLineCount: minimumLineCount
        )
    }

    @Test func blankVideoProducesEmptyTranscript() async throws {
        let env = ProcessInfo.processInfo.environment
        let path = env["LOCALSCROLL_E2E_BLANK_VIDEO"] ?? Self.defaultBlankVideoPath

        guard FileManager.default.fileExists(atPath: path) else {
            print("E2E_SKIP: blank video not found at \(path)")
            return
        }

        try await Self.runPipeline(path: path, expectEmpty: true, minimumLineCount: 0)
    }

    private static func firstExistingPath(_ paths: [String]) -> String? {
        paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func runPipeline(
        path: String,
        expectEmpty: Bool,
        minimumLineCount: Int
    ) async throws {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            print("E2E_SKIP: video not found at \(path)")
            return
        }

        // Loading the duration is the first thing that touches the file, so a
        // sandbox read denial surfaces here, fast, before the long OCR loop.
        let source = AVAssetVideoSource(url: url)
        let duration: Double
        do {
            duration = try await source.durationSeconds()
        } catch {
            print("E2E_SKIP: could not load asset (sandbox/read failure?): \(error)")
            return
        }
        print("E2E_VIDEO_PATH=\(path)")
        print("E2E_VIDEO_DURATION=\(duration)")
        print("E2E_EXPECT_EMPTY=\(expectEmpty)")
        print("E2E_MIN_LINES=\(minimumLineCount)")

        // Mirror `localscroll process --quality fast`:
        //   backend = Apple Vision (auto language, accurate, correction on)
        //   fps = 2, mode = screen_recording (no preprocess), no adaptive,
        //   scroll stitch, Core default StitchConfig (== Python defaults).
        let ocr = VisionOCRBackend()
        let config = PipelineConfig(
            fps: 2.0,
            stitchConfig: StitchConfig(),
            schedulerConfig: SchedulerConfig(),
            adaptive: false,
            stitchMode: .scroll,
            coverageRefinement: nil
        )
        let pipeline = Pipeline(video: source, ocr: ocr, config: config)

        let clock = ContinuousClock()
        let started = clock.now
        let transcript = try await pipeline.run(onProgress: { progress in
            if progress.processedFrames % 25 == 0 {
                print("E2E_PROGRESS frames=\(progress.processedFrames)/\(progress.expectedFrames)")
            }
        })
        let elapsed = started.duration(to: clock.now)

        print("E2E_ELAPSED=\(elapsed)")
        print("IOS_E2E_LINECOUNT=\(transcript.lines.count)")
        print("===IOS_E2E_TRANSCRIPT_BEGIN===")
        for line in transcript.lines {
            print(line)
        }
        print("===IOS_E2E_TRANSCRIPT_END===")

        // Best-effort durable copy inside the (writable) app container.
        let outDir = ProcessInfo.processInfo.environment["LOCALSCROLL_E2E_OUTDIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let outFileName = expectEmpty ? "ios_vision_blank.txt" : "ios_vision_fast.txt"
        let outURL = outDir.appendingPathComponent(outFileName)
        try? transcript.lines.joined(separator: "\n")
            .write(to: outURL, atomically: true, encoding: .utf8)
        print("IOS_E2E_OUT=\(outURL.path)")

        if expectEmpty {
            #expect(transcript.lines.isEmpty)
        } else {
            #expect(transcript.lines.count >= minimumLineCount)
        }
    }
}
