import Foundation
import PhotosUI
import SwiftUI

/// One entry in the sequential processing queue. Not persisted — it represents
/// in-flight work; the finished result is written to a `HistoryRecord`.
@MainActor
final class QueueItem: ObservableObject, Identifiable {
    enum Status: Equatable {
        case pending
        case processing
        case paused
        case done
        case failed(String)
    }

    let id = UUID()

    /// Source of the work: either a freshly picked photo item, or a cached video URL
    /// (used when re-processing from history).
    enum Source {
        case picker(PhotosPickerItem)
        case importedFile(processingFileName: String, originalFileName: String)
        case cachedVideo(url: URL, fileName: String)
        case checkpoint(ProcessingCheckpoint)
    }

    /// Mutable so the queue can re-point a running item at its on-disk
    /// `ProcessingCheckpoint` once processing begins. This lets a pause/resume
    /// (manual or triggered by background-task expiration) continue from the
    /// saved progress instead of restarting the video from the first frame.
    var source: Source
    @Published var displayName: String
    @Published var originalFileName: String?
    @Published var status: Status = .pending
    @Published var progressFraction: Double = 0
    @Published var statusText: String = ""

    let qualityPreset: QualityPreset
    let captionMode: Bool
    let cleanupEnabled: Bool

    init(
        source: Source,
        displayName: String,
        originalFileName: String? = nil,
        qualityPreset: QualityPreset,
        captionMode: Bool,
        cleanupEnabled: Bool
    ) {
        self.source = source
        self.displayName = displayName
        self.originalFileName = originalFileName
        self.qualityPreset = qualityPreset
        self.captionMode = captionMode
        self.cleanupEnabled = cleanupEnabled
    }

    var isFinished: Bool {
        switch status {
        case .done, .failed: return true
        case .pending, .processing, .paused: return false
        }
    }
}
