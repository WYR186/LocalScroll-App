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
        case done
        case failed(String)
    }

    let id = UUID()

    /// Source of the work: either a freshly picked photo item, or a cached video URL
    /// (used when re-processing from history).
    enum Source {
        case picker(PhotosPickerItem)
        case cachedVideo(url: URL, fileName: String)
    }

    let source: Source
    @Published var displayName: String
    @Published var status: Status = .pending
    @Published var progressFraction: Double = 0
    @Published var statusText: String = ""

    let qualityPreset: QualityPreset
    let captionMode: Bool
    let cleanupEnabled: Bool

    init(
        source: Source,
        displayName: String,
        qualityPreset: QualityPreset,
        captionMode: Bool,
        cleanupEnabled: Bool
    ) {
        self.source = source
        self.displayName = displayName
        self.qualityPreset = qualityPreset
        self.captionMode = captionMode
        self.cleanupEnabled = cleanupEnabled
    }

    var isFinished: Bool {
        switch status {
        case .done, .failed: return true
        case .pending, .processing: return false
        }
    }
}
