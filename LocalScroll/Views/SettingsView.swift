import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKeys.cacheOriginalVideos) private var cacheOriginalVideos = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Cache Original Videos", isOn: $cacheOriginalVideos)
                } header: {
                    Text("Storage")
                } footer: {
                    Text("When on, processed videos are kept in the app so you can re-process the same video from History. Uses more storage.")
                }

                Section {
                    NavigationLink {
                        CachedVideoManagerView()
                    } label: {
                        Label("Manage Cached Videos", systemImage: "internaldrive")
                    }
                }

                Section {
                    Label("All processing runs on-device. LocalScroll collects no data.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
