import Foundation
import UIKit

@MainActor
final class BackgroundTaskController {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    func begin(name: String, expiration: @escaping @MainActor () -> Void) {
        end()
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            Task { @MainActor in
                expiration()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
