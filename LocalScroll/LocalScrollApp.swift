import SwiftData
import SwiftUI

@main
struct LocalScrollApp: App {
    @AppStorage(SettingsKeys.appearance) private var appearance = AppearancePreference.system

    init() {
        BackgroundProcessingScheduler.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(for: [HistoryRecord.self, ProcessingCheckpoint.self])
    }
}
