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
    /// Incremented whenever the current task is externally interrupted (pause / delete).
    /// Lets the old task's cleanup closure detect that it's been superseded.
    private var taskGeneration: Int = 0
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
        taskGeneration += 1
        task?.cancel()
        task = nil
        isRunning = false
        for item in queue where item.status == .processing {
            item.status = .failed("Canceled")
            item.statusText = "Canceled"
        }
    }

    func clearFinished() {
        queue.removeAll { $0.isFinished }
    }

    func clearQueue() {
        cancel()
        queue.removeAll()
    }

    // MARK: - Per-item pause / resume

    /// Pauses the given item. If it is currently processing, the running task is
    /// cancelled and the queue moves on to the next pending item automatically.
    func pauseItem(_ item: QueueItem) {
        switch item.status {
        case .processing:
            item.status = .paused
            item.statusText = "Paused — will restart from beginning"
            item.progressFraction = 0
            taskGeneration += 1
            task?.cancel()
            task = nil
            isRunning = false
            startIfNeeded()   // continue with remaining pending items
        case .pending:
            item.status = .paused
            item.statusText = "Paused"
        default:
            break
        }
    }

    func resumeItem(_ item: QueueItem) {
        guard item.status == .paused else { return }
        item.status = .pending
        item.statusText = ""
        startIfNeeded()
    }

    func togglePause(_ item: QueueItem) {
        switch item.status {
        case .processing, .pending: pauseItem(item)
        case .paused:               resumeItem(item)
        default:                    break
        }
    }

    // MARK: - Per-item delete + reorder

    func deleteItem(_ item: QueueItem) {
        if item.status == .processing {
            taskGeneration += 1
            task?.cancel()
            task = nil
            isRunning = false
        }
        queue.removeAll { $0.id == item.id }
        startIfNeeded()   // no-op if nothing is pending
    }

    func delete(at offsets: IndexSet) {
        let targets = offsets.map { queue[$0] }
        for item in targets where item.status == .processing {
            taskGeneration += 1
            task?.cancel()
            task = nil
            isRunning = false
        }
        queue.remove(atOffsets: offsets)
        startIfNeeded()
    }

    func move(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Processing loop

    private func startIfNeeded() {
        guard task == nil else { return }
        guard queue.contains(where: { $0.status == .pending }) else { return }
        isRunning = true
        let gen = taskGeneration
        task = Task { [weak self] in
            await self?.runLoop()
            await MainActor.run {
                // Only clean up if this is still the current task generation;
                // prevents a superseded task from nilling a replacement task.
                guard let self, self.taskGeneration == gen else { return }
                self.isRunning = false
                self.task = nil
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
            // pauseItem() already set status to .paused — don't overwrite it.
            if item.status == .processing {
                item.status = .failed("Canceled")
                item.statusText = "Canceled"
            }
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
        let language = OCRLanguagePreference(
            rawValue: UserDefaults.standard.string(forKey: SettingsKeys.ocrLanguage) ?? ""
        ) ?? .automatic
        let ocr = VisionOCRBackend(
            recognitionLanguages: language.recognitionLanguages,
            automaticallyDetectsLanguage: language.automaticallyDetectsLanguage
        )
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
                stitchMode: captionMode ? .caption : .scroll,
                coverageRefinement: preset.coverageRefinementConfig
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
    static let appearance          = "appearance"
    static let ocrLanguage         = "ocrLanguage"
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
