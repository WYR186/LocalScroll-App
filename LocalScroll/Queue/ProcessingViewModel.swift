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
    private var backgroundTask: BackgroundTaskController?
    private var backgroundExpirationRequested = false
    private let liveActivity = ProcessingLiveActivityController()
    private var notificationObservers: [NSObjectProtocol] = []
    /// Incremented whenever the current task is externally interrupted (pause / delete).
    /// Lets the old task's cleanup closure detect that it's been superseded.
    private var taskGeneration: Int = 0
    private weak var modelContext: ModelContext?

    /// Whether the original video should be cached for re-processing.
    private var cacheOriginalVideos: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.cacheOriginalVideos)
    }

    init() {
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: .localScrollBackgroundProcessingRequested,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.restoreCheckpointedItems()
                    self?.startIfNeeded()
                }
            }
        )
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: .localScrollBackgroundProcessingExpired,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.pauseCurrentForBackgroundExpiration()
                }
            }
        )
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var hasFinishedItems: Bool {
        queue.contains { $0.isFinished }
    }

    func attach(context: ModelContext) {
        modelContext = context
        restoreCheckpointedItems()
        BackgroundProcessingScheduler.shared.schedule()
        startIfNeeded()
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
        backgroundTask?.end()
        backgroundTask = nil
        isRunning = false
        for item in queue where item.status == .processing {
            item.status = .failed("Canceled")
            item.statusText = "Canceled"
            deleteCheckpoint(for: item)
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
            item.statusText = "Paused — progress saved"
            taskGeneration += 1
            task?.cancel()
            task = nil
            backgroundTask?.end()
            backgroundTask = nil
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
            backgroundTask?.end()
            backgroundTask = nil
            isRunning = false
        }
        deleteCheckpoint(for: item)
        queue.removeAll { $0.id == item.id }
        startIfNeeded()   // no-op if nothing is pending
    }

    func delete(at offsets: IndexSet) {
        let targets = offsets.map { queue[$0] }
        for item in targets where item.status == .processing {
            taskGeneration += 1
            task?.cancel()
            task = nil
            backgroundTask?.end()
            backgroundTask = nil
            isRunning = false
        }
        for item in targets {
            deleteCheckpoint(for: item)
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
                BackgroundProcessingScheduler.shared.complete(success: true)
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
        backgroundExpirationRequested = false
        item.statusText = "Importing video..."

        var tempURLToDelete: URL?
        var checkpoint: ProcessingCheckpoint?
        var processingFileNameToDelete: String?
        do {
            // 1. Resolve the video URL.
            let videoURL: URL
            let preCachedFileName: String?
            let resumeState: PipelineResumeState?
            switch item.source {
            case .picker(let pickerItem):
                guard let movie = try await pickerItem.loadTransferable(type: SelectedMovie.self) else {
                    throw LocalScrollUIError.videoImportFailed
                }
                let processingFileName = try ProcessingVideoStore.store(videoURL: movie.url)
                guard let storedURL = ProcessingVideoStore.url(for: processingFileName) else {
                    throw LocalScrollUIError.videoImportFailed
                }
                let newCheckpoint = ProcessingCheckpoint(
                    displayName: item.displayName,
                    processingVideoFileName: processingFileName,
                    preCachedVideoFileName: nil,
                    qualityPreset: item.qualityPreset,
                    captionMode: item.captionMode,
                    cleanupEnabled: item.cleanupEnabled
                )
                modelContext?.insert(newCheckpoint)
                try? modelContext?.save()
                checkpoint = newCheckpoint
                videoURL = storedURL
                tempURLToDelete = movie.url
                preCachedFileName = nil
                resumeState = nil
            case .cachedVideo(let url, let fileName):
                let processingFileName = try ProcessingVideoStore.store(videoURL: url)
                guard let storedURL = ProcessingVideoStore.url(for: processingFileName) else {
                    throw LocalScrollUIError.videoImportFailed
                }
                let newCheckpoint = ProcessingCheckpoint(
                    displayName: item.displayName,
                    processingVideoFileName: processingFileName,
                    preCachedVideoFileName: fileName,
                    qualityPreset: item.qualityPreset,
                    captionMode: item.captionMode,
                    cleanupEnabled: item.cleanupEnabled
                )
                modelContext?.insert(newCheckpoint)
                try? modelContext?.save()
                checkpoint = newCheckpoint
                videoURL = storedURL
                preCachedFileName = fileName
                resumeState = nil
            case .checkpoint(let savedCheckpoint):
                guard let storedURL = ProcessingVideoStore.url(for: savedCheckpoint.processingVideoFileName) else {
                    throw LocalScrollUIError.checkpointVideoMissing
                }
                checkpoint = savedCheckpoint
                videoURL = storedURL
                preCachedFileName = savedCheckpoint.preCachedVideoFileName
                item.progressFraction = savedCheckpoint.progressFraction
                let samples = savedCheckpoint.decodedSamples
                let startSeconds = samples.last.map {
                    $0.timestamp + max(0.01, 0.5 / max(1, item.qualityPreset.fps))
                } ?? savedCheckpoint.lastTimestamp
                resumeState = PipelineResumeState(
                    baseSamples: samples,
                    startSeconds: startSeconds
                )
            }
            processingFileNameToDelete = checkpoint?.processingVideoFileName

            backgroundTask = BackgroundTaskController()
            backgroundTask?.begin(name: "LocalScroll video processing") { [weak self, weak item] in
                guard let self else { return }
                pauseCurrentForBackgroundExpiration(item: item)
            }
            liveActivity.start(
                videoName: item.displayName,
                progress: item.progressFraction,
                status: item.statusText
            )

            // 2. Build + run the pipeline.
            item.statusText = "Preparing frames..."
            let pipeline = Self.buildPipeline(
                videoURL: videoURL,
                preset: item.qualityPreset,
                captionMode: item.captionMode
            )
            let result = try await pipeline.run(
                resumeState: resumeState,
                checkpointEveryFrames: 12,
                onCheckpoint: { [weak self, weak item, weak checkpoint] snapshot in
                    await MainActor.run {
                        guard let self, let item, let checkpoint else { return }
                        checkpoint.update(
                            with: snapshot,
                            progressFraction: item.progressFraction
                        )
                        try? self.modelContext?.save()
                        BackgroundProcessingScheduler.shared.schedule()
                    }
                },
                onProgress: { [weak item] progress in
                await MainActor.run {
                    guard let item else { return }
                    item.progressFraction = progress.fractionCompleted
                    item.statusText = Self.progressText(progress)
                    Task {
                        await self.liveActivity.update(
                            progress: item.progressFraction,
                            status: item.statusText
                        )
                    }
                }
                }
            )

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
            if let checkpoint {
                modelContext?.delete(checkpoint)
            }
            try? modelContext?.save()

            lastFinishedName = item.displayName
            lastFinishedLines = record.displayLines
            item.progressFraction = 1
            item.statusText = record.lineCount == 1 ? "1 line" : "\(record.lineCount) lines"
            item.status = .done
            await liveActivity.end(progress: 1, status: item.statusText)
            if let processingFileNameToDelete {
                ProcessingVideoStore.delete(processingFileNameToDelete)
            }
        } catch is CancellationError {
            if backgroundExpirationRequested {
                item.status = .paused
                item.statusText = "Paused — progress saved"
                await liveActivity.end(progress: item.progressFraction, status: item.statusText)
            } else if item.status == .processing {
                item.status = .failed("Canceled")
                item.statusText = "Canceled"
                await liveActivity.end(progress: item.progressFraction, status: item.statusText)
            }
        } catch {
            item.status = .failed(error.localizedDescription)
            await liveActivity.end(progress: item.progressFraction, status: item.statusText)
        }

        // Clean up the temp import unless it was cached (caching makes its own copy).
        if let tempURLToDelete {
            try? FileManager.default.removeItem(at: tempURLToDelete)
        }
        backgroundTask?.end()
        backgroundTask = nil
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

    private func restoreCheckpointedItems() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<ProcessingCheckpoint>(
            sortBy: [SortDescriptor(\.updatedAt)]
        )
        guard let checkpoints = try? modelContext.fetch(descriptor), !checkpoints.isEmpty else {
            return
        }

        let existingIDs: Set<UUID> = Set(queue.compactMap { item in
            if case .checkpoint(let checkpoint) = item.source {
                return checkpoint.id
            }
            return nil
        })
        for checkpoint in checkpoints where !existingIDs.contains(checkpoint.id) {
            let preset = QualityPreset(rawValue: checkpoint.qualityPreset) ?? .smart
            let item = QueueItem(
                source: .checkpoint(checkpoint),
                displayName: checkpoint.displayName,
                qualityPreset: preset,
                captionMode: checkpoint.captionMode,
                cleanupEnabled: checkpoint.cleanupEnabled
            )
            item.progressFraction = checkpoint.progressFraction
            item.statusText = "Resume ready"
            queue.append(item)
        }
    }

    private func deleteCheckpoint(for item: QueueItem) {
        guard case .checkpoint(let checkpoint) = item.source else { return }
        ProcessingVideoStore.delete(checkpoint.processingVideoFileName)
        modelContext?.delete(checkpoint)
        try? modelContext?.save()
    }

    private func pauseCurrentForBackgroundExpiration(item: QueueItem? = nil) {
        backgroundExpirationRequested = true
        let currentItem = item ?? queue.first { $0.status == .processing }
        if let currentItem {
            currentItem.status = .paused
            currentItem.statusText = "Paused — progress saved"
        }
        taskGeneration += 1
        task?.cancel()
        task = nil
        isRunning = false
        backgroundTask?.end()
        backgroundTask = nil
        BackgroundProcessingScheduler.shared.schedule()
    }
}

enum SettingsKeys {
    static let cacheOriginalVideos = "cacheOriginalVideos"
    static let appearance          = "appearance"
    static let ocrLanguage         = "ocrLanguage"
}

enum LocalScrollUIError: Error, LocalizedError {
    case videoImportFailed
    case checkpointVideoMissing

    var errorDescription: String? {
        switch self {
        case .videoImportFailed:
            return "Could not import the selected video."
        case .checkpointVideoMissing:
            return "The saved processing video is missing."
        }
    }
}
