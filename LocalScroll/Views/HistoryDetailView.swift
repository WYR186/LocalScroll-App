import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct HistoryDetailView: View {
    let record: HistoryRecord

    @EnvironmentObject private var model: ProcessingViewModel
    @State private var showCleaned: Bool

    init(record: HistoryRecord) {
        self.record = record
        _showCleaned = State(initialValue: record.preferredCleaned)
    }

    private var hasCleaned: Bool { record.cleanedLines != nil }

    private var lines: [String] {
        if showCleaned, let cleaned = record.cleanedLines { return cleaned }
        return record.rawLines
    }

    private var text: String { lines.joined(separator: "\n") }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.regularMaterial)

            Divider()

            ScrollView {
                Text(text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
        }
        .navigationTitle(record.fileName)
        .navigationBarTitleDisplayModeInlineIfAvailable()
        .toolbar {
            if !text.isEmpty {
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ThumbnailImage(data: record.thumbnailData)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
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

            if hasCleaned {
                Picker("Transcript", selection: $showCleaned) {
                    Text("Cleaned").tag(true)
                    Text("Raw").tag(false)
                }
                .pickerStyle(.segmented)
            }

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

    private func reprocess(cached: String) {
        guard let url = VideoCacheStore.url(for: cached) else { return }
        model.enqueueCachedVideo(url: url, fileName: cached, displayName: record.fileName)
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
