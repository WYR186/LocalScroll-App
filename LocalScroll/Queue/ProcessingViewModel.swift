import Foundation
import LocalScrollCore
import PhotosUI
import SwiftData
import SwiftUI

/// Drives sequential (one-at-a-time) processing of a queue of videos and writes
/// each finished result into SwiftData history.
@MainActor
final class ProcessingViewModel: ObservableObject {
    // Picker settings (bound by the UI).
    @Published var qualityPreset: QualityPreset = .smart
    @Published var captionMode = false
    @Published var cleanupEnabled = false

    // Queue + last finished preview.
    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastFinishedName: String?
    @Published private(set) var lastFinishedLines: [String] = []
    /// Bumped when work is enqueued from another tab (e.g. re-process from History),
    /// signalling the UI to focus the Extract tab.
    @Published private(set) var focusExtractToken = 0

    private var task: Task<Void, Never>?
    private weak var modelContext: ModelContext?

    /// Whether the original video should be cached for re-processing.
    private var cacheOriginalVideos: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.cacheOriginalVideos)
    }

    var hasFinishedItems: Bool {
        queue.contains { $0.isFinished }
    }

    func attach(context: ModelContext) {
        modelContext = context
    }

    // MARK: - Enqueue

    func enqueue(items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        for item in items {
            let name = item.itemIdentifier ?? "Video \(queue.count + 1)"
            queue.append(
                QueueItem(
                    source: .picker(item),
                    displayName: name,
                    qualityPreset: qualityPreset,
                    captionMode: captionMode,
                    cleanupEnabled: cleanupEnabled
                )
            )
        }
        startIfNeeded()
    }

    func enqueueCachedVideo(url: URL, fileName: String, displayName: String) {
        queue.append(
            QueueItem(
                source: .cachedVideo(url: url, fileName: fileName),
                displayName: displayName,
                qualityPreset: qualityPreset,
                captionMode: captionMode,
                cleanupEnabled: cleanupEnabled
            )
        )
        focusExtractToken += 1
        startIfNeeded()
    }

    // MARK: - Queue control

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
        for item in queue where item.status == .processing {
            item.status = .failed("Canceled")
        }
    }

    func clearFinished() {
        queue.removeAll { $0.isFinished }
    }

    func clearQueue() {
        cancel()
        queue.removeAll()
    }

    // MARK: - Processing loop

    private func startIfNeeded() {
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in
            await self?.runLoop()
            await MainActor.run {
                self?.isRunning = false
                self?.task = nil
            }
        }
    }

    private func runLoop() async {
        while let item = queue.first(where: { $0.status == .pending }) {
            if Task.isCancelled { break }
            await process(item)
        }
    }

    private func process(_ item: QueueItem) async {
        item.status = .processing
        item.progressFraction = 0
        item.statusText = "Importing video..."

        var tempURLToDelete: URL?
        do {
            // 1. Resolve the video URL.
            let videoURL: URL
            let preCachedFileName: String?
            switch item.source {
            case .picker(let pickerItem):
                guard let movie = try await pickerItem.loadTransferable(type: SelectedMovie.self) else {
                    throw LocalScrollUIError.videoImportFailed
                }
                videoURL = movie.url
                tempURLToDelete = movie.url
                preCachedFileName = nil
            case .cachedVideo(let url, let fileName):
                videoURL = url
                preCachedFileName = fileName
            }

            // 2. Build + run the pipeline.
            item.statusText = "Preparing frames..."
            let pipeline = Self.buildPipeline(
                videoURL: videoURL,
                preset: item.qualityPreset,
                captionMode: item.captionMode
            )
            let result = try await pipeline.run { [weak item] progress in
                await MainActor.run {
                    guard let item else { return }
                    item.progressFraction = progress.fractionCompleted
                    item.statusText = Self.progressText(progress)
                }
            }

            // 3. Optional AI cleanup.
            var rawLines = result.lines
            var cleanedLines: [String]?
            var preferredCleaned = false
            if item.cleanupEnabled {
                item.statusText = "Cleaning transcript..."
                let cleaner = FoundationModelTranscriptCleaner()
                let cleanup = try await cleaner.cleanup(result)
                rawLines = cleanup.rawTranscript.lines
                cleanedLines = cleanup.cleanedTranscript.lines
                preferredCleaned = cleanup.didChange
            }

            // 4. Thumbnail + duration.
            item.statusText = "Saving to history..."
            let thumbnail = try await VideoThumbnail.generate(url: videoURL)
            let duration = (try? await AVAssetVideoSource(url: videoURL).durationSeconds()) ?? 0

            // 5. Cache handling.
            let cachedFileName: String?
            if let preCachedFileName {
                cachedFileName = preCachedFileName        // already cached (re-process)
            } else if cacheOriginalVideos {
                cachedFileName = try? VideoCacheStore.store(tempURL: videoURL)
            } else {
                cachedFileName = nil
            }

            // 6. Persist.
            let record = HistoryRecord(
                fileName: item.displayName,
                durationSeconds: duration,
                thumbnailData: thumbnail,
                rawLines: rawLines,
                cleanedLines: cleanedLines,
                preferredCleaned: preferredCleaned,
                qualityPreset: item.qualityPreset.rawValue,
                captionMode: item.captionMode,
                cachedVideoFileName: cachedFileName
            )
            modelContext?.insert(record)
            try? modelContext?.save()

            lastFinishedName = item.displayName
            lastFinishedLines = record.displayLines
            item.progressFraction = 1
            item.statusText = record.lineCount == 1 ? "1 line" : "\(record.lineCount) lines"
            item.status = .done
        } catch is CancellationError {
            item.status = .failed("Canceled")
        } catch {
            item.status = .failed(error.localizedDescription)
        }

        // Clean up the temp import unless it was cached (caching makes its own copy).
        if let tempURLToDelete {
            try? FileManager.default.removeItem(at: tempURLToDelete)
        }
    }

    // MARK: - Helpers

    /// Assembles the extraction pipeline for one video. Shared by the queue and any
    /// single-video entry point.
    static func buildPipeline(
        videoURL: URL,
        preset: QualityPreset,
        captionMode: Bool
    ) -> Pipeline {
        let source = AVAssetVideoSource(url: videoURL)
        let ocr = VisionOCRBackend()
        let motion = preset.usesAdaptiveSampling ? VisionMotionEstimator() : nil
        let preprocessor = preset.usesPreprocessing ? CoreImagePreprocessor() : nil
        return Pipeline(
            video: source,
            ocr: ocr,
            motion: motion,
            preprocessor: preprocessor,
            config: PipelineConfig(
                fps: preset.fps,
                stitchConfig: preset.stitchConfig,
                schedulerConfig: preset.schedulerConfig,
                adaptive: preset.usesAdaptiveSampling,
                stitchMode: captionMode ? .caption : .scroll
            )
        )
    }

    static func progressText(_ progress: PipelineProgress) -> String {
        var chunks = [
            "Frame \(progress.processedFrames) of \(progress.expectedFrames)",
            "\(progress.recognizedLines) OCR lines",
        ]
        if progress.skippedFrames > 0 {
            chunks.append("\(progress.skippedFrames) skipped")
        }
        if let scrollState = progress.scrollState {
            chunks.append(scrollState.rawValue)
        }
        return chunks.joined(separator: " - ")
    }
}

enum SettingsKeys {
    static let cacheOriginalVideos = "cacheOriginalVideos"
}

enum LocalScrollUIError: Error, LocalizedError {
    case videoImportFailed

    var errorDescription: String? {
        switch self {
        case .videoImportFailed:
            return "Could not import the selected video."
        }
    }
}
