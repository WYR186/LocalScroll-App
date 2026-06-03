import SwiftData
import SwiftUI

@main
struct LocalScrollApp: App {
    @AppStorage(SettingsKeys.appearance) private var appearance = AppearancePreference.system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(for: HistoryRecord.self)
    }
}
