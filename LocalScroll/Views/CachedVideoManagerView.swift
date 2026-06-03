import SwiftData
import SwiftUI

struct CachedVideoManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var videos: [VideoCacheStore.CachedVideo] = []

    var body: some View {
        List {
            if videos.isEmpty {
                ContentUnavailableView(
                    "No Cached Videos",
                    systemImage: "internaldrive",
                    description: Text("Enable “Cache Original Videos” in Settings to keep videos for re-processing.")
                )
            } else {
                Section {
                    ForEach(videos) { video in
                        HStack {
                            Text(video.fileName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(formatted(video.sizeBytes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Total: \(formatted(VideoCacheStore.totalSizeBytes()))")
                }

                Section {
                    Button(role: .destructive) {
                        deleteAll()
                    } label: {
                        Label("Delete All Cached Videos", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Cached Videos")
        .onAppear(perform: reload)
    }

    private func reload() {
        videos = VideoCacheStore.allCached()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            removeReference(to: videos[index].fileName)
            VideoCacheStore.delete(videos[index].fileName)
        }
        reload()
    }

    private func deleteAll() {
        for video in videos {
            removeReference(to: video.fileName)
        }
        VideoCacheStore.deleteAll()
        reload()
    }

    /// Clear the cached-video pointer on any history record referencing this file,
    /// so the detail screen no longer offers re-processing a missing file.
    private func removeReference(to fileName: String) {
        guard let all = try? modelContext.fetch(FetchDescriptor<HistoryRecord>()) else { return }
        var changed = false
        for record in all where record.cachedVideoFileName == fileName {
            record.cachedVideoFileName = nil
            changed = true
        }
        if changed { try? modelContext.save() }
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
