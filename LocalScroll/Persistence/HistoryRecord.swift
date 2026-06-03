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
    var fileName: String
    var durationSeconds: Double

    /// JPEG thumbnail of the source video, ~400px wide.
    @Attribute(.externalStorage) var thumbnailData: Data

    var rawLines: [String]
    var cleanedLines: [String]?
    /// Whether the cleaned transcript was the one preferred for display.
    var preferredCleaned: Bool
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
        durationSeconds: Double,
        thumbnailData: Data,
        rawLines: [String],
        cleanedLines: [String]?,
        preferredCleaned: Bool,
        qualityPreset: String,
        captionMode: Bool,
        cachedVideoFileName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.fileName = fileName
        self.durationSeconds = durationSeconds
        self.thumbnailData = thumbnailData
        self.rawLines = rawLines
        self.cleanedLines = cleanedLines
        self.preferredCleaned = preferredCleaned
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
}
