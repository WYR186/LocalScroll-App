import SwiftData
import SwiftUI

struct HistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HistoryRecord.createdAt, order: .reverse) private var records: [HistoryRecord]

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
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let record = records[index]
            if let cached = record.cachedVideoFileName {
                VideoCacheStore.delete(cached)
            }
            modelContext.delete(record)
        }
        try? modelContext.save()
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
