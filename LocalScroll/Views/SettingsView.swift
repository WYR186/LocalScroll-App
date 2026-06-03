import SwiftUI

// MARK: - Appearance preference

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    /// Resolved SwiftUI ColorScheme, or nil to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Settings view

struct SettingsView: View {
    @AppStorage(SettingsKeys.appearance)          private var appearance         = AppearancePreference.system
    @AppStorage(SettingsKeys.cacheOriginalVideos) private var cacheOriginalVideos = false

    var body: some View {
        NavigationStack {
            Form {
                // ── Appearance ────────────────────────────────────────────
                Section {
                    Picker(selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { pref in
                            Label(pref.title, systemImage: pref.icon).tag(pref)
                        }
                    } label: {
                        Label("Appearance", systemImage: appearance.icon)
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("System follows your device's Dark Mode switch in Settings.")
                }

                // ── Storage ───────────────────────────────────────────────
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

                // ── Privacy ───────────────────────────────────────────────
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
