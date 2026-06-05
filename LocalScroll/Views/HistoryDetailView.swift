import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private enum HistoryDetailPane: String, Hashable {
    case summary
    case cleaned
    case raw
}

struct HistoryDetailView: View {
    let record: HistoryRecord

    @EnvironmentObject private var model: ProcessingViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var selectedPane: HistoryDetailPane = .summary
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isGeneratingSummary = false
    @State private var summaryProgressText: String?
    @State private var summaryErrorMessage: String?
    @State private var summaryTask: Task<Void, Never>?

    private var hasCleaned: Bool { record.cleanedLines != nil }

    private var summaryText: String? {
        guard let summary = record.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else {
            return nil
        }
        return record.summaryText
    }

    private var selectedText: String {
        switch selectedPane {
        case .summary:
            return summaryText ?? ""
        case .cleaned:
            return record.cleanedLines?.joined(separator: "\n") ?? ""
        case .raw:
            return record.rawLines.joined(separator: "\n")
        }
    }

    private var sourceHasText: Bool {
        !FoundationModelTranscriptSummarizer.normalizedLines(record.summarySourceLines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.regularMaterial)

            Divider()

            ScrollView {
                detailContent
                    .padding(18)
            }
        }
        .navigationTitle(record.fileName)
        .navigationBarTitleDisplayModeInlineIfAvailable()
        .toolbar {
            Button {
                beginRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            if !selectedText.isEmpty {
                Button {
                    copy(selectedText)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                ShareLink(item: selectedText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .alert("Rename Video", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Save") {
                commitRename()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The original video file name is preserved separately.")
        }
        .alert("Summary Failed", isPresented: summaryErrorPresented) {
            Button("OK", role: .cancel) {
                summaryErrorMessage = nil
            }
        } message: {
            Text(summaryErrorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ThumbnailImage(data: record.thumbnailData)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.fileName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Label(record.originalVideoFileName, systemImage: "film")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(record.lineCount) lines · \(DurationFormat.string(record.durationSeconds))")
                        .font(.subheadline)
                    Text("\(record.qualityPreset.capitalized)\(record.captionMode ? " · Caption" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(record.createdAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Picker("Content", selection: $selectedPane) {
                Text("Summary").tag(HistoryDetailPane.summary)
                if hasCleaned {
                    Text("Cleaned").tag(HistoryDetailPane.cleaned)
                }
                Text("Raw").tag(HistoryDetailPane.raw)
            }
            .pickerStyle(.segmented)

            if let cached = record.cachedVideoFileName, VideoCacheStore.url(for: cached) != nil {
                Button {
                    reprocess(cached: cached)
                } label: {
                    Label("Re-process Video", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedPane {
        case .summary:
            summaryContent
        case .cleaned, .raw:
            Text(selectedText)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isGeneratingSummary {
                VStack(alignment: .leading, spacing: 12) {
                    ProgressView {
                        Text(summaryProgressText ?? "Generating summary...")
                    }

                    Button(role: .cancel) {
                        cancelSummaryGeneration()
                    } label: {
                        Label("Cancel Summary", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let summaryText {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(summaryMetadataText, systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            generateSummary()
                        } label: {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canGenerateSummary)
                    }

                    Text(summaryText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ContentUnavailableView(
                        "No Summary",
                        systemImage: "list.bullet.rectangle",
                        description: Text(summaryUnavailableText)
                    )

                    Button {
                        generateSummary()
                    } label: {
                        Label("Generate Summary", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canGenerateSummary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canGenerateSummary: Bool {
        guard sourceHasText else { return false }
        if case .available = FoundationModelTranscriptSummarizer.currentAvailability {
            return true
        }
        return false
    }

    private var summaryUnavailableText: String {
        guard sourceHasText else {
            return "This history item has no transcript text to summarize."
        }
        if case .available = FoundationModelTranscriptSummarizer.currentAvailability {
            return "Generate a detailed on-device outline from the \(record.preferredSummarySourceKind.title) transcript."
        }
        return FoundationModelTranscriptSummarizer.availabilityMessage
    }

    private var summaryMetadataText: String {
        let source = SummarySourceKind(rawValue: record.summarySourceKind ?? "") ?? record.preferredSummarySourceKind
        guard let generatedAt = record.summaryGeneratedAt else {
            return "Generated from \(source.title)"
        }
        return "Generated from \(source.title) \(generatedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func reprocess(cached: String) {
        guard let url = VideoCacheStore.url(for: cached) else { return }
        model.enqueueCachedVideo(
            url: url,
            fileName: cached,
            displayName: record.fileName,
            originalFileName: record.originalVideoFileName
        )
    }

    private func beginRename() {
        renameText = record.fileName
        isRenaming = true
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        record.fileName = trimmed
        try? modelContext.save()
    }

    private func generateSummary() {
        guard !isGeneratingSummary else { return }

        let sourceKind = record.preferredSummarySourceKind
        let sourceLines = record.summarySourceLines
        guard sourceHasText else {
            summaryErrorMessage = FoundationModelTranscriptSummarizerError.emptyTranscript.localizedDescription
            return
        }
        guard case .available = FoundationModelTranscriptSummarizer.currentAvailability else {
            summaryErrorMessage = FoundationModelTranscriptSummarizer.availabilityMessage
            return
        }

        isGeneratingSummary = true
        summaryProgressText = "Preparing summary..."
        summaryErrorMessage = nil

        summaryTask = Task {
            do {
                let summarizer = FoundationModelTranscriptSummarizer()
                let result = try await summarizer.summarize(
                    lines: sourceLines,
                    sourceKind: sourceKind
                ) { progress in
                    await MainActor.run {
                        summaryProgressText = progress.message
                    }
                }

                await MainActor.run {
                    record.applySummary(result)
                    try? modelContext.save()
                    selectedPane = .summary
                    finishSummaryGeneration()
                }
            } catch is CancellationError {
                await MainActor.run {
                    finishSummaryGeneration()
                }
            } catch {
                await MainActor.run {
                    summaryErrorMessage = error.localizedDescription
                    finishSummaryGeneration()
                }
            }
        }
    }

    private func cancelSummaryGeneration() {
        summaryTask?.cancel()
        finishSummaryGeneration()
    }

    private func finishSummaryGeneration() {
        isGeneratingSummary = false
        summaryProgressText = nil
        summaryTask = nil
    }

    private var summaryErrorPresented: Binding<Bool> {
        Binding {
            summaryErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                summaryErrorMessage = nil
            }
        }
    }

    private func copy(_ string: String) {
#if os(iOS)
        UIPasteboard.general.string = string
#elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
#endif
    }
}

private extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeInlineIfAvailable() -> some View {
#if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }
}
