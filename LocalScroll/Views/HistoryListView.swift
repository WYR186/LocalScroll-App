import SwiftData
import SwiftUI

/// Pure search + quality-preset filter for History, extracted so the matching
/// rules can be unit-tested independently of the view.
enum HistoryFilter {
    static func apply(to records: [HistoryRecord], query: String, preset: QualityPreset?) -> [HistoryRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter { record in
            let matchesPreset = preset == nil || record.qualityPreset == preset?.rawValue
            let matchesQuery = trimmed.isEmpty
                || record.fileName.localizedCaseInsensitiveContains(trimmed)
                || record.originalVideoFileName.localizedCaseInsensitiveContains(trimmed)
            return matchesPreset && matchesQuery
        }
    }
}

struct HistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HistoryRecord.createdAt, order: .reverse) private var records: [HistoryRecord]

    @State private var recordToRename: HistoryRecord?
    @State private var renameText = ""
    @State private var searchText = ""
    @State private var presetFilter: QualityPreset?

    /// Records after applying the search query and the preset filter.
    private var filteredRecords: [HistoryRecord] {
        HistoryFilter.apply(to: records, query: searchText, preset: presetFilter)
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Processed videos and their recognized subtitles appear here.")
                    )
                } else if filteredRecords.isEmpty {
                    noMatchesView
                } else {
                    List {
                        ForEach(filteredRecords) { record in
                            NavigationLink {
                                HistoryDetailView(record: record)
                            } label: {
                                HistoryRow(record: record)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    beginRename(record)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(records: [record])
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    beginRename(record)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    delete(records: [record])
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Search history")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !records.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !records.isEmpty {
                        filterMenu
                    }
                }
            }
            .alert("Rename Video", isPresented: renamePresented) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    commitRename()
                }
                Button("Cancel", role: .cancel) {
                    recordToRename = nil
                    renameText = ""
                }
            } message: {
                Text("The original video file name is preserved separately.")
            }
        }
    }

    /// Pull-down menu that filters the list by the quality preset used.
    private var filterMenu: some View {
        Menu {
            Picker("Quality Preset", selection: $presetFilter) {
                Text("All Presets").tag(QualityPreset?.none)
                ForEach(QualityPreset.allCases) { preset in
                    Text(preset.title).tag(QualityPreset?.some(preset))
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: presetFilter == nil
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
    }

    /// Shown when there are records but the search/filter excludes them all.
    @ViewBuilder
    private var noMatchesView: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty, let presetFilter {
            ContentUnavailableView(
                "No \(presetFilter.title) Extractions",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("No history matches the selected quality preset.")
            )
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    private func delete(at offsets: IndexSet) {
        delete(records: offsets.map { filteredRecords[$0] })
    }

    private func delete(records recordsToDelete: [HistoryRecord]) {
        for record in recordsToDelete {
            if let cached = record.cachedVideoFileName {
                VideoCacheStore.delete(cached)
            }
            modelContext.delete(record)
        }
        try? modelContext.save()
    }

    private func beginRename(_ record: HistoryRecord) {
        recordToRename = record
        renameText = record.fileName
    }

    private func commitRename() {
        guard let recordToRename else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordToRename.fileName = trimmed
        try? modelContext.save()
        self.recordToRename = nil
        renameText = ""
    }

    private var renamePresented: Binding<Bool> {
        Binding {
            recordToRename != nil
        } set: { isPresented in
            if !isPresented {
                recordToRename = nil
                renameText = ""
            }
        }
    }
}

private struct HistoryRow: View {
    let record: HistoryRecord

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailImage(data: record.thumbnailData)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    Text(DurationFormat.string(record.durationSeconds))
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(3)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(record.originalVideoFileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Label("\(record.lineCount)", systemImage: "text.alignleft")
                    if record.cachedVideoFileName != nil {
                        Image(systemName: "internaldrive")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(record.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
