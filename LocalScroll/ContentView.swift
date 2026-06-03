import LocalScrollCore
import PhotosUI
import SwiftUI

enum AppTab: Hashable {
    case extract, history, settings
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var model = ProcessingViewModel()
    @State private var tab: AppTab = .extract

    var body: some View {
        TabView(selection: $tab) {
            ExtractView()
                .tabItem { Label("Extract", systemImage: "text.viewfinder") }
                .tag(AppTab.extract)

            HistoryListView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .environmentObject(model)
        .onAppear { model.attach(context: modelContext) }
        .onChange(of: model.focusExtractToken) { _, _ in
            tab = .extract
        }
    }
}

// MARK: - Extract tab

struct ExtractView: View {
    @EnvironmentObject private var model: ProcessingViewModel
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controlBar
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(.regularMaterial)

                Divider()

                content
            }
            .navigationTitle("LocalScroll")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !model.queue.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if model.isRunning {
                        Button(role: .cancel) {
                            model.cancel()
                        } label: {
                            Label("Cancel All", systemImage: "xmark")
                        }
                    }
                }
            }
            .onChange(of: selectedItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                model.enqueue(items: newItems)
                selectedItems = []
            }
        }
    }

    private var controlBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(
                selection: $selectedItems,
                matching: .videos
            ) {
                Label("Choose Videos", systemImage: "video.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 12) {
                Picker("Quality", selection: $model.qualityPreset) {
                    ForEach(QualityPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $model.captionMode) {
                    Text("Caption")
                }
                .toggleStyle(.switch)
            }

            if FoundationModelTranscriptCleaner.isSupportedOnCurrentOS {
                Toggle(isOn: $model.cleanupEnabled) {
                    Text("AI Cleanup")
                }
                .toggleStyle(.switch)
                .disabled(!canEnableCleanup)
            }

            Label("On-device processing. Selected videos stay in the app container, and LocalScroll collects no data.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.queue.isEmpty {
            ContentUnavailableView(
                "No Videos Queued",
                systemImage: "text.page",
                description: Text("Choose one or more videos to extract scrolling text. They process one at a time and are saved to History.")
            )
        } else {
            List {
                Section {
                    ForEach(model.queue) { item in
                        QueueRow(item: item) {
                            model.togglePause(item)
                        }
                    }
                    .onMove(perform: model.move)
                    .onDelete { offsets in
                        model.delete(at: offsets)
                    }
                } header: {
                    HStack {
                        Text("Queue")
                        Spacer()
                        if model.hasFinishedItems {
                            Button("Clear Finished") { model.clearFinished() }
                                .font(.caption)
                        }
                    }
                }

                if !model.lastFinishedLines.isEmpty {
                    Section("Last Result — \(model.lastFinishedName ?? "")") {
                        Text(model.lastFinishedLines.joined(separator: "\n"))
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var canEnableCleanup: Bool {
        if case .available = FoundationModelTranscriptCleaner.currentAvailability {
            return true
        }
        return false
    }
}

private struct QueueRow: View {
    @ObservedObject var item: QueueItem
    @Environment(\.editMode) private var editMode
    let onTogglePause: () -> Void

    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.status == .processing {
                    ProgressView(value: item.progressFraction)
                        .progressViewStyle(.linear)
                        .animation(.linear(duration: 0.3), value: item.progressFraction)
                }
                if !item.statusText.isEmpty {
                    Text(item.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Pause / resume button — hidden while drag-handles are showing.
            if !isEditing {
                actionButton
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Status icon (left)

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .processing:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.75)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: Action button (right)

    @ViewBuilder
    private var actionButton: some View {
        switch item.status {
        case .processing:
            Button(action: onTogglePause) {
                Image(systemName: "pause.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)

        case .paused:
            Button(action: onTogglePause) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

        case .pending:
            Button(action: onTogglePause) {
                Image(systemName: "pause.circle")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)

        default:
            EmptyView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: HistoryRecord.self, inMemory: true)
}
