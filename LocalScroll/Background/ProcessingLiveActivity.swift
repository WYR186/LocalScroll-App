import Foundation

/// Semantic stage of a video extraction, shared by the in-app queue and the
/// Live Activity. Declared outside the `ActivityKit` guard so the no-op
/// controller can use it too.
///
/// Raw values are part of the Live Activity's serialized `ContentState` and must
/// stay byte-identical with the widget target's copy in
/// `LocalScrollWidget/ProcessingActivityAttributes.swift`.
enum ProcessingPhase: String, Codable, Hashable {
    case importing
    case preparing
    case extracting
    case cleaning
    case summarizing
    case saving
    case done
    case paused
    case failed
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

struct ProcessingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var progress: Double
        var phase: ProcessingPhase
        /// OCR lines recognized so far (or the final count when done).
        var lineCount: Int
        /// Optional short clause, e.g. a failure reason or "Progress saved".
        var detail: String?
    }

    var videoName: String
}

@MainActor
final class ProcessingLiveActivityController {
    private var activity: Activity<ProcessingActivityAttributes>?

    func start(videoName: String, progress: Double, phase: ProcessingPhase, lineCount: Int = 0, detail: String? = nil) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ProcessingActivityAttributes(videoName: videoName)
        let content = ActivityContent(
            state: ProcessingActivityAttributes.ContentState(progress: progress, phase: phase, lineCount: lineCount, detail: detail),
            staleDate: Date(timeIntervalSinceNow: 15 * 60)
        )
        activity = try? Activity.request(attributes: attributes, content: content)
    }

    func update(progress: Double, phase: ProcessingPhase, lineCount: Int = 0, detail: String? = nil) async {
        guard let activity else { return }
        let content = ActivityContent(
            state: ProcessingActivityAttributes.ContentState(progress: progress, phase: phase, lineCount: lineCount, detail: detail),
            staleDate: Date(timeIntervalSinceNow: 15 * 60)
        )
        await activity.update(content)
    }

    func end(progress: Double, phase: ProcessingPhase, lineCount: Int = 0, detail: String? = nil) async {
        guard let activity else { return }
        let content = ActivityContent(
            state: ProcessingActivityAttributes.ContentState(progress: progress, phase: phase, lineCount: lineCount, detail: detail),
            staleDate: nil
        )
        await activity.end(content, dismissalPolicy: .after(Date(timeIntervalSinceNow: 60)))
        self.activity = nil
    }
}
#else

@MainActor
final class ProcessingLiveActivityController {
    func start(videoName: String, progress: Double, phase: ProcessingPhase, lineCount: Int = 0, detail: String? = nil) {}
    func update(progress: Double, phase: ProcessingPhase, lineCount: Int = 0, detail: String? = nil) async {}
    func end(progress: Double, phase: ProcessingPhase, lineCount: Int = 0, detail: String? = nil) async {}
}
#endif
