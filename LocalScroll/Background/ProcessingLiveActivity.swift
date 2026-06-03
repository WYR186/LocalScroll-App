#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

struct ProcessingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var progress: Double
        var status: String
    }

    var videoName: String
}

@MainActor
final class ProcessingLiveActivityController {
    private var activity: Activity<ProcessingActivityAttributes>?

    func start(videoName: String, progress: Double, status: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ProcessingActivityAttributes(videoName: videoName)
        let content = ActivityContent(
            state: ProcessingActivityAttributes.ContentState(
                progress: progress,
                status: status
            ),
            staleDate: Date(timeIntervalSinceNow: 15 * 60)
        )
        activity = try? Activity.request(attributes: attributes, content: content)
    }

    func update(progress: Double, status: String) async {
        guard let activity else { return }
        let content = ActivityContent(
            state: ProcessingActivityAttributes.ContentState(
                progress: progress,
                status: status
            ),
            staleDate: Date(timeIntervalSinceNow: 15 * 60)
        )
        await activity.update(content)
    }

    func end(progress: Double, status: String) async {
        guard let activity else { return }
        let content = ActivityContent(
            state: ProcessingActivityAttributes.ContentState(
                progress: progress,
                status: status
            ),
            staleDate: nil
        )
        await activity.end(content, dismissalPolicy: .after(Date(timeIntervalSinceNow: 60)))
        self.activity = nil
    }
}
#else
import Foundation

@MainActor
final class ProcessingLiveActivityController {
    func start(videoName: String, progress: Double, status: String) {}
    func update(progress: Double, status: String) async {}
    func end(progress: Double, status: String) async {}
}
#endif
