import Foundation
import SwiftData

/// A persisted record of one finished extraction.
///
/// Stores enough to identify the source video (thumbnail, name, duration) and the
/// recognized subtitle lines, so history survives `Clear` and app relaunches.
@Model
final class HistoryRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    /// User-editable display title for this extraction.
    var fileName: String
    /// Original source video file name, preserved separately from the editable title.
    var originalFileName: String?
    var durationSeconds: Double

    /// JPEG thumbnail of the source video, ~400px wide.
    @Attribute(.externalStorage) var thumbnailData: Data

    var rawLines: [String]
    var cleanedLines: [String]?
    /// Whether the cleaned transcript was the one preferred for display.
    var preferredCleaned: Bool
    /// Detailed on-device summary generated from `cleanedLines` when available, else `rawLines`.
    var summaryText: String?
    var summaryGeneratedAt: Date?
    var summarySourceKind: String?
    var summaryPromptVersion: String?
    var lineCount: Int

    var qualityPreset: String
    var captionMode: Bool

    /// File name (relative to the cached-videos directory) when the original video
    /// was cached locally for re-processing; `nil` otherwise.
    var cachedVideoFileName: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        fileName: String,
        originalFileName: String? = nil,
        durationSeconds: Double,
        thumbnailData: Data,
        rawLines: [String],
        cleanedLines: [String]?,
        preferredCleaned: Bool,
        summaryText: String? = nil,
        summaryGeneratedAt: Date? = nil,
        summarySourceKind: String? = nil,
        summaryPromptVersion: String? = nil,
        qualityPreset: String,
        captionMode: Bool,
        cachedVideoFileName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.fileName = fileName
        self.originalFileName = originalFileName
        self.durationSeconds = durationSeconds
        self.thumbnailData = thumbnailData
        self.rawLines = rawLines
        self.cleanedLines = cleanedLines
        self.preferredCleaned = preferredCleaned
        self.summaryText = summaryText
        self.summaryGeneratedAt = summaryGeneratedAt
        self.summarySourceKind = summarySourceKind
        self.summaryPromptVersion = summaryPromptVersion
        self.lineCount = (preferredCleaned ? cleanedLines : rawLines)?.count ?? rawLines.count
        self.qualityPreset = qualityPreset
        self.captionMode = captionMode
        self.cachedVideoFileName = cachedVideoFileName
    }

    /// Lines preferred for display (cleaned if available and preferred, else raw).
    var displayLines: [String] {
        if preferredCleaned, let cleanedLines { return cleanedLines }
        return rawLines
    }

    var summarySourceLines: [String] {
        if let cleanedLines, !cleanedLines.isEmpty {
            return cleanedLines
        }
        return rawLines
    }

    var preferredSummarySourceKind: SummarySourceKind {
        if let cleanedLines, !cleanedLines.isEmpty {
            return .cleaned
        }
        return .raw
    }

    func applySummary(_ result: TranscriptSummaryResult) {
        summaryText = result.summaryText
        summaryGeneratedAt = result.generatedAt
        summarySourceKind = result.sourceKind.rawValue
        summaryPromptVersion = result.promptVersion
    }

    var originalVideoFileName: String {
        guard let originalFileName, !originalFileName.isEmpty else { return fileName }
        return originalFileName
    }
}
