import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import LocalScrollCore
import Testing
@testable import LocalScroll

struct AdapterPhaseTests {
    @Test func avAssetVideoSourceSamplesContiguousFrames() async throws {
        let url = try await makeTestMovie(frameCount: 45, sourceFPS: 20, size: CGSize(width: 160, height: 90))
        defer { try? FileManager.default.removeItem(at: url) }

        let source = AVAssetVideoSource(url: url)
        let duration = try await source.durationSeconds()
        let expected = Int(ceil(duration * 2.0))

        var frames: [VideoFrame] = []
        for try await frame in source.frames(targetFPS: 2.0) {
            frames.append(frame)
        }

        #expect(abs(frames.count - expected) <= 1)
        #expect(frames.map(\.idx) == Array(0..<frames.count))
        #expect(frames.allSatisfy { $0.width == 160 && $0.height == 90 })

        let timestamps = frames.map(\.timestamp)
        #expect(zip(timestamps, timestamps.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func visionBoundingBoxConvertsToTopLeftPixels() {
        let bbox = visionBoundingBoxToBBox(
            CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            imageWidth: 200,
            imageHeight: 100
        )

        #expect(bbox == BBox(x: 50, y: 25, w: 100, h: 50))
    }

    @Test func visionOCRReadsGeneratedStillFrame() async throws {
        let image = try makeTextImage("LocalScroll", size: CGSize(width: 640, height: 240))
        let frame = VideoFrame(idx: 0, timestamp: 0, image: image)
        let backend = VisionOCRBackend(recognitionLanguages: ["en-US"])

        let lines = try await backend.detect(in: frame)
        let joined = lines.map(\.text).joined(separator: " ")

        #expect(joined.localizedCaseInsensitiveContains("LocalScroll"))
    }

    @Test func coreImagePreprocessorScalesFrameForOCR() async throws {
        let image = try makeTextImage("LocalScroll", size: CGSize(width: 640, height: 240))
        let frame = VideoFrame(idx: 7, timestamp: 3.5, image: image)
        let preprocessor = CoreImagePreprocessor(
            config: CoreImagePreprocessorConfig(scale: 0.5)
        )

        let processed = try await preprocessor.process(frame)

        #expect(processed.idx == frame.idx)
        #expect(processed.timestamp == frame.timestamp)
        #expect(processed.width == 320)
        #expect(processed.height == 120)
    }
}

private func makeTestMovie(
    frameCount: Int,
    sourceFPS: Int,
    size: CGSize
) async throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mov")

    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
    )
    input.expectsMediaDataInRealTime = false

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ]
    )

    guard writer.canAdd(input) else {
        throw TestMovieError.cannotAddWriterInput
    }
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    for idx in 0..<frameCount {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        let pixelBuffer = try makePixelBuffer(
            width: Int(size.width),
            height: Int(size.height),
            seed: UInt8(idx % 255)
        )
        let time = CMTime(value: CMTimeValue(idx), timescale: CMTimeScale(sourceFPS))
        guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
            throw writer.error ?? TestMovieError.appendFailed
        }
    }

    input.markAsFinished()
    await writer.finishWriting()

    if writer.status == .failed {
        throw writer.error ?? TestMovieError.finishFailed
    }

    return url
}

private func makePixelBuffer(width: Int, height: Int, seed: UInt8) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        nil,
        width,
        height,
        kCVPixelFormatType_32ARGB,
        nil,
        &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else {
        throw TestMovieError.pixelBufferFailed
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw TestMovieError.pixelBufferFailed
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let byteCount = bytesPerRow * height
    memset(baseAddress, Int32(seed), byteCount)

    return pixelBuffer
}

private func makeTextImage(_ text: String, size: CGSize) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw TestMovieError.imageFailed
    }

    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    context.setFillColor(CGColor(gray: 0, alpha: 1))

    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 72, nil)
    let attributed = NSAttributedString(
        string: text,
        attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0, alpha: 1),
        ]
    )
    let line = CTLineCreateWithAttributedString(attributed)
    context.textPosition = CGPoint(x: 48, y: 100)
    CTLineDraw(line, context)

    guard let image = context.makeImage() else {
        throw TestMovieError.imageFailed
    }
    return image
}

private enum TestMovieError: Error {
    case cannotAddWriterInput
    case appendFailed
    case finishFailed
    case pixelBufferFailed
    case imageFailed
}
