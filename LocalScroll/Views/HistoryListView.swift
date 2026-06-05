import SwiftData
import SwiftUI

struct HistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HistoryRecord.createdAt, order: .reverse) private var records: [HistoryRecord]

    @State private var recordToRename: HistoryRecord?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Processed videos and their recognized subtitles appear here.")
                    )
                } else {
                    List {
                        ForEach(records) { record in
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
            .toolbar {
                if !records.isEmpty {
                    EditButton()
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

    private func delete(at offsets: IndexSet) {
        delete(records: offsets.map { records[$0] })
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
