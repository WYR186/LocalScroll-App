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

enum OCRLanguagePreference: String, CaseIterable, Identifiable {
    case automatic = "automatic"
    case english = "english"
    case simplifiedChinese = "simplifiedChinese"
    case traditionalChinese = "traditionalChinese"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:          return "Automatic"
        case .english:            return "English"
        case .simplifiedChinese:  return "Simplified Chinese"
        case .traditionalChinese: return "Traditional Chinese"
        }
    }

    var recognitionLanguages: [String] {
        switch self {
        case .automatic:          return []
        case .english:            return ["en-US"]
        case .simplifiedChinese:  return ["zh-Hans"]
        case .traditionalChinese: return ["zh-Hant"]
        }
    }

    var automaticallyDetectsLanguage: Bool {
        self == .automatic
    }
}

// MARK: - Settings view

struct SettingsView: View {
    @AppStorage(SettingsKeys.appearance)          private var appearance         = AppearancePreference.system
    @AppStorage(SettingsKeys.cacheOriginalVideos) private var cacheOriginalVideos = false
    @AppStorage(SettingsKeys.ocrLanguage)         private var ocrLanguage        = OCRLanguagePreference.automatic

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

                // ── OCR ───────────────────────────────────────────────────
                Section {
                    Picker(selection: $ocrLanguage) {
                        ForEach(OCRLanguagePreference.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    } label: {
                        Label("OCR Language", systemImage: "text.viewfinder")
                    }
                } header: {
                    Text("Recognition")
                } footer: {
                    Text("Choosing one language is faster and usually more reliable when your videos are not mixed-language.")
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
