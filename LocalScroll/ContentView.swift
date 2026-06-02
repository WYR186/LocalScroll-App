import LocalScrollCore
import PhotosUI
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ContentView: View {
    @StateObject private var model = ExtractionViewModel()
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controlBar
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(.regularMaterial)

                Divider()

                transcriptArea
            }
            .navigationTitle("LocalScroll")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if model.isProcessing {
                        Button(role: .cancel) {
                            model.cancel()
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                    }

                    if let text = model.transcriptText, !text.isEmpty {
                        Button {
                            copy(text)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        ShareLink(item: text) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                model.start(item: newItem)
            }
        }
    }

    private var controlBar: some View {
        let pickerTitle = model.hasTranscript ? "Choose Another" : "Choose Video"

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedItem, matching: .videos) {
                    Label(pickerTitle, systemImage: "video")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isProcessing)

                if model.hasTranscript {
                    Button {
                        model.reset()
                        selectedItem = nil
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 12) {
                Picker("Quality", selection: $model.qualityPreset) {
                    ForEach(QualityPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.isProcessing)

                Toggle(isOn: $model.captionMode) {
                    Text("Caption")
                }
                .toggleStyle(.switch)
                .disabled(model.isProcessing)
            }

            if model.shouldShowCleanupControl {
                Toggle(isOn: $model.cleanupEnabled) {
                    Text("AI Cleanup")
                }
                .toggleStyle(.switch)
                .disabled(model.isProcessing || !model.canEnableCleanup)
            }

            if model.hasCleanedTranscript {
                Picker("Transcript", selection: $model.transcriptDisplayMode) {
                    ForEach(TranscriptDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.isProcessing)
            }

            if model.isProcessing {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: model.progressFraction)
                    Text(model.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else if let statusText = model.idleStatusText {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Label("On-device processing. Selected videos stay in the app container, and LocalScroll collects no data.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var transcriptArea: some View {
        if let transcriptText = model.transcriptText, !transcriptText.isEmpty {
            ScrollView {
                Text(transcriptText)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .background(transcriptBackground)
        } else if model.errorMessage != nil {
            ContentUnavailableView(
                "Extraction Failed",
                systemImage: "exclamationmark.triangle",
                description: Text("Choose another video or try a different quality preset.")
            )
        } else if model.didFinishEmpty {
            ContentUnavailableView(
                "No Text Found",
                systemImage: "text.magnifyingglass",
                description: Text("The selected video finished processing, but OCR did not find transcript text.")
            )
        } else if model.wasCanceled {
            ContentUnavailableView(
                "Processing Canceled",
                systemImage: "xmark.circle",
                description: Text("Choose a video to start again.")
            )
        } else {
            ContentUnavailableView(
                "No Transcript",
                systemImage: "text.page",
                description: Text(model.isProcessing ? "Recognizing text from the selected video." : "Choose a video to extract scrolling text.")
            )
        }
    }

    private func copy(_ text: String) {
#if os(iOS)
        UIPasteboard.general.string = text
#elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
    }
}

@MainActor
private final class ExtractionViewModel: ObservableObject {
    @Published var progress: PipelineProgress?
    @Published var statusText = ""
    @Published var idleStatusText: String?
    @Published private var rawTranscript: Transcript?
    @Published private var cleanedTranscript: Transcript?
    @Published var errorMessage: String?
    @Published var isProcessing = false
    @Published var qualityPreset: QualityPreset = .smart
    @Published var captionMode = false
    @Published var cleanupEnabled = false
    @Published var transcriptDisplayMode: TranscriptDisplayMode = .cleaned
    @Published private(set) var didFinishEmpty = false
    @Published private(set) var wasCanceled = false

    private var task: Task<Void, Never>?
    private var selectedVideoURL: URL?

    var hasTranscript: Bool {
        transcriptText?.isEmpty == false
    }

    var hasCleanedTranscript: Bool {
        cleanedTranscript != nil
    }

    var shouldShowCleanupControl: Bool {
        FoundationModelTranscriptCleaner.isSupportedOnCurrentOS
    }

    var canEnableCleanup: Bool {
        if case .available = FoundationModelTranscriptCleaner.currentAvailability {
            return true
        }
        return false
    }

    var transcriptText: String? {
        displayedTranscript?.lines.joined(separator: "\n")
    }

    var progressFraction: Double {
        progress?.fractionCompleted ?? 0
    }

    private var displayedTranscript: Transcript? {
        switch transcriptDisplayMode {
        case .cleaned:
            return cleanedTranscript ?? rawTranscript
        case .raw:
            return rawTranscript
        }
    }

    func start(item: PhotosPickerItem?) {
        guard let item else { return }
        cancel()

        errorMessage = nil
        rawTranscript = nil
        cleanedTranscript = nil
        progress = nil
        statusText = "Importing video..."
        idleStatusText = nil
        didFinishEmpty = false
        wasCanceled = false
        isProcessing = true

        task = Task {
            do {
                guard let movie = try await item.loadTransferable(type: SelectedMovie.self) else {
                    throw LocalScrollUIError.videoImportFailed
                }

                selectedVideoURL = movie.url
                statusText = "Preparing frames..."

                let preset = qualityPreset
                let captionMode = captionMode
                let source = AVAssetVideoSource(url: movie.url)
                let ocr = VisionOCRBackend()
                let motion = preset.usesAdaptiveSampling ? VisionMotionEstimator() : nil
                let preprocessor = preset.usesPreprocessing ? CoreImagePreprocessor() : nil
                let pipeline = Pipeline(
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

                let result = try await pipeline.run { [weak self] progress in
                    await MainActor.run {
                        self?.progress = progress
                        self?.statusText = Self.progressText(progress)
                    }
                }

                rawTranscript = result
                cleanedTranscript = nil
                transcriptDisplayMode = .cleaned

                if cleanupEnabled {
                    statusText = "Cleaning transcript..."
                    let cleaner = FoundationModelTranscriptCleaner()
                    let cleanup = try await cleaner.cleanup(result)
                    rawTranscript = cleanup.rawTranscript
                    cleanedTranscript = cleanup.cleanedTranscript
                    transcriptDisplayMode = cleanup.didChange ? .cleaned : .raw
                }

                isProcessing = false
                statusText = ""
                let lineCount = displayedTranscript?.lines.count ?? result.lines.count
                didFinishEmpty = lineCount == 0
                idleStatusText = lineCount == 1 ? "1 line extracted" : "\(lineCount) lines extracted"
            } catch is CancellationError {
                isProcessing = false
                statusText = ""
                wasCanceled = true
                idleStatusText = "Processing canceled"
            } catch {
                isProcessing = false
                statusText = ""
                idleStatusText = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func reset() {
        cancel()
        rawTranscript = nil
        cleanedTranscript = nil
        progress = nil
        errorMessage = nil
        statusText = ""
        idleStatusText = nil
        isProcessing = false
        didFinishEmpty = false
        wasCanceled = false

        if let selectedVideoURL {
            try? FileManager.default.removeItem(at: selectedVideoURL)
        }
        selectedVideoURL = nil
    }

    private static func progressText(_ progress: PipelineProgress) -> String {
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

private enum TranscriptDisplayMode: String, CaseIterable, Identifiable {
    case cleaned
    case raw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cleaned: return "Cleaned"
        case .raw: return "Raw"
        }
    }
}

private enum LocalScrollUIError: Error, LocalizedError {
    case videoImportFailed

    var errorDescription: String? {
        switch self {
        case .videoImportFailed:
            return "Could not import the selected video."
        }
    }
}

private var transcriptBackground: Color {
#if os(iOS)
    Color(.systemBackground)
#elseif os(macOS)
    Color(nsColor: .textBackgroundColor)
#else
    Color.clear
#endif
}

#Preview {
    ContentView()
}
