import Foundation
import Testing
import UniformTypeIdentifiers
@testable import LocalScroll

struct HistoryAndImportTests {
    @Test func historyRenameKeepsOriginalVideoFileName() {
        let record = HistoryRecord(
            fileName: "Trip receipt",
            originalFileName: "IMG_0427.MOV",
            durationSeconds: 12,
            thumbnailData: Data(),
            rawLines: ["Alpha", "Beta"],
            cleanedLines: nil,
            preferredCleaned: false,
            qualityPreset: QualityPreset.smart.rawValue,
            captionMode: false
        )

        record.fileName = "Renamed receipt"

        #expect(record.fileName == "Renamed receipt")
        #expect(record.originalVideoFileName == "IMG_0427.MOV")
        #expect(record.displayLines == ["Alpha", "Beta"])
        #expect(record.summarySourceLines == ["Alpha", "Beta"])
        #expect(record.preferredSummarySourceKind == .raw)
    }

    @Test func legacyHistoryFallsBackToEditableNameWhenOriginalNameIsMissing() {
        let record = HistoryRecord(
            fileName: "Old imported video",
            durationSeconds: 8,
            thumbnailData: Data(),
            rawLines: ["One line"],
            cleanedLines: nil,
            preferredCleaned: false,
            qualityPreset: QualityPreset.fast.rawValue,
            captionMode: true
        )

        #expect(record.originalVideoFileName == "Old imported video")
        #expect(record.summaryText == nil)
        #expect(record.summaryGeneratedAt == nil)
        #expect(record.summarySourceKind == nil)
        #expect(record.summaryPromptVersion == nil)
    }

    @Test func supportedVideoTypesIncludeCommonFilesFormatsWithoutDuplicates() {
        let identifiers = SupportedVideoTypes.importableTypes.map(\.identifier)
        let uniqueIdentifiers = Set(identifiers)

        #expect(identifiers.count == uniqueIdentifiers.count)
        #expect(SupportedVideoTypes.importableTypes.contains { $0.conforms(to: .video) })
        #expect(SupportedVideoTypes.importableTypes.contains(.movie))
        #expect(SupportedVideoTypes.importableTypes.contains(UTType(filenameExtension: "mp4")!))
        #expect(SupportedVideoTypes.importableTypes.contains(UTType(filenameExtension: "mkv")!))
        #expect(SupportedVideoTypes.importableTypes.contains(UTType(filenameExtension: "webm")!))
    }

    @MainActor
    @Test func failedImportStatusTextDoesNotLookInProgress() {
        let status = ProcessingViewModel.failureStatusText(for: LocalScrollUIError.videoImportFailed)

        #expect(status == "Could not import the selected video.")
        #expect(status != "Importing video...")
    }

    @Test func processingCheckpointPersistsOriginalFileNameForResume() {
        let checkpoint = ProcessingCheckpoint(
            displayName: "Lecture notes",
            originalFileName: "lecture-source.mp4",
            processingVideoFileName: "processing-copy.mp4",
            preCachedVideoFileName: nil,
            qualityPreset: .smart,
            captionMode: false,
            cleanupEnabled: false
        )

        #expect(checkpoint.displayName == "Lecture notes")
        #expect(checkpoint.originalFileName == "lecture-source.mp4")
    }
}
