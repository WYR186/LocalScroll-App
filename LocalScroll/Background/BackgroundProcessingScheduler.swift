#if os(iOS)
import BackgroundTasks
import Foundation

extension Notification.Name {
    static let localScrollBackgroundProcessingRequested = Notification.Name(
        "localScrollBackgroundProcessingRequested"
    )
    static let localScrollBackgroundProcessingExpired = Notification.Name(
        "localScrollBackgroundProcessingExpired"
    )
}

@MainActor
final class BackgroundProcessingScheduler {
    static let shared = BackgroundProcessingScheduler()
    static let identifier = "com.wyr186.localscroll.processing"

    private var activeTask: BGProcessingTask?
    private var registered = false

    private init() {}

    func register() {
        guard !registered else { return }
        registered = true
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.identifier,
            using: nil
        ) { task in
            Task { @MainActor in
                guard let task = task as? BGProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.activeTask = task
                task.expirationHandler = {
                    Task { @MainActor in
                        NotificationCenter.default.post(
                            name: .localScrollBackgroundProcessingExpired,
                            object: nil
                        )
                        self.complete(success: false)
                    }
                }
                NotificationCenter.default.post(
                    name: .localScrollBackgroundProcessingRequested,
                    object: nil
                )
            }
        }
    }

    func schedule() {
        let request = BGProcessingTaskRequest(identifier: Self.identifier)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func complete(success: Bool) {
        activeTask?.setTaskCompleted(success: success)
        activeTask = nil
        schedule()
    }
}
#else
import Foundation

extension Notification.Name {
    static let localScrollBackgroundProcessingRequested = Notification.Name(
        "localScrollBackgroundProcessingRequested"
    )
    static let localScrollBackgroundProcessingExpired = Notification.Name(
        "localScrollBackgroundProcessingExpired"
    )
}

@MainActor
final class BackgroundProcessingScheduler {
    static let shared = BackgroundProcessingScheduler()
    static let identifier = "com.wyr186.localscroll.processing"

    private init() {}

    func register() {}
    func schedule() {}
    func complete(success: Bool) {}
}
#endif
