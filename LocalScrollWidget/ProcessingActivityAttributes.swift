import ActivityKit
import Foundation

/// Mirror of the app target's `ProcessingPhase`. Both copies are part of the
/// Live Activity's serialized state and must stay byte-identical (raw values).
/// See `LocalScroll/Background/ProcessingLiveActivity.swift`.
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
