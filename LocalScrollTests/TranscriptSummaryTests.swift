import Foundation
import Testing
@testable import LocalScroll

struct TranscriptSummaryTests {
    @Test func summarySourcePrefersCleanedLines() {
        let source = FoundationModelTranscriptSummarizer.sourceLines(
            rawLines: ["raw one", "raw two"],
            cleanedLines: ["clean one", "clean two"]
        )

        #expect(source.0 == .cleaned)
        #expect(source.1 == ["clean one", "clean two"])
    }

    @Test func summarySourceFallsBackToRawWhenCleanedIsEmpty() {
        let source = FoundationModelTranscriptSummarizer.sourceLines(
            rawLines: ["raw one", "raw two"],
            cleanedLines: [" ", "\n"]
        )

        #expect(source.0 == .raw)
        #expect(source.1 == ["raw one", "raw two"])
    }

    @Test func shortTranscriptUsesOneChunk() {
        let chunks = FoundationModelTranscriptSummarizer.chunks(
            for: ["Alpha ships today.", "Beta follows tomorrow."],
            maxEstimatedTokens: 400
        )

        #expect(chunks.count == 1)
        #expect(chunks.first?.startLine == 1)
        #expect(chunks.first?.endLine == 2)
    }

    @Test func longEnglishTranscriptSplitsIntoOrderedChunks() {
        let lines = (1...40).map { index in
            "Line \(index): alpha beta gamma delta epsilon zeta eta theta iota kappa lambda."
        }
        let chunks = FoundationModelTranscriptSummarizer.chunks(
            for: lines,
            maxEstimatedTokens: 220
        )

        #expect(chunks.count > 1)
        #expect(chunks.first?.startLine == 1)
        #expect(chunks.last?.endLine == lines.count)
        #expect(chunks.flatMap(\.lines) == lines)
    }

    @Test func longCJKTranscriptSplitsIntoOrderedChunks() {
        let line = "今天我们整理会议记录，包含任务、日期、负责人、风险、决定和后续行动。"
        let lines = Array(repeating: line, count: 80)
        let chunks = FoundationModelTranscriptSummarizer.chunks(
            for: lines,
            maxEstimatedTokens: 220
        )

        #expect(chunks.count > 1)
        #expect(chunks.first?.startLine == 1)
        #expect(chunks.last?.endLine == lines.count)
        #expect(chunks.flatMap(\.lines) == lines)
    }

    @Test func singleOversizedLineStaysInOneChunk() {
        let oversized = String(repeating: "A very dense sentence with many details. ", count: 200)
        let chunks = FoundationModelTranscriptSummarizer.chunks(
            for: [oversized],
            maxEstimatedTokens: 220
        )

        #expect(chunks.count == 1)
        #expect(chunks.first?.lines == [oversized.trimmingCharacters(in: .whitespacesAndNewlines)])
        #expect((chunks.first?.estimatedTokens ?? 0) > 220)
    }

    @Test func summaryGenerationModesChooseExpectedAutomaticBehavior() {
        #expect(!SummaryGenerationMode.manual.shouldGenerateAfterProcessing(cleanupEnabled: true))
        #expect(SummaryGenerationMode.afterProcessing.shouldGenerateAfterProcessing(cleanupEnabled: false))
        #expect(SummaryGenerationMode.afterProcessing.shouldGenerateAfterProcessing(cleanupEnabled: true))
        #expect(!SummaryGenerationMode.withCleanup.shouldGenerateAfterProcessing(cleanupEnabled: false))
        #expect(SummaryGenerationMode.withCleanup.shouldGenerateAfterProcessing(cleanupEnabled: true))
    }

    @Test func historyRecordAppliesSummaryResult() {
        let record = HistoryRecord(
            fileName: "Lecture",
            originalFileName: "lecture.mov",
            durationSeconds: 42,
            thumbnailData: Data(),
            rawLines: ["Raw"],
            cleanedLines: ["Cleaned"],
            preferredCleaned: true,
            qualityPreset: QualityPreset.smart.rawValue,
            captionMode: false
        )
        let date = Date(timeIntervalSince1970: 42)
        let result = TranscriptSummaryResult(
            summaryText: "# Detailed Summary\n- Cleaned",
            sourceKind: .cleaned,
            promptVersion: "test-version",
            generatedAt: date
        )

        record.applySummary(result)

        #expect(record.summaryText == result.summaryText)
        #expect(record.summarySourceKind == SummarySourceKind.cleaned.rawValue)
        #expect(record.summaryPromptVersion == "test-version")
        #expect(record.summaryGeneratedAt == date)
    }

    @Test func mockSummarizerCanGenerateAndApplySummary() async throws {
        let record = HistoryRecord(
            fileName: "Demo",
            durationSeconds: 12,
            thumbnailData: Data(),
            rawLines: ["Raw line"],
            cleanedLines: ["Cleaned line"],
            preferredCleaned: true,
            qualityPreset: QualityPreset.fast.rawValue,
            captionMode: false
        )
        let summarizer = MockTranscriptSummarizer(summaryText: "# Detailed Summary\n- Cleaned line")
        let result = try await summarizer.summarize(
            lines: record.summarySourceLines,
            sourceKind: record.preferredSummarySourceKind,
            onProgress: nil
        )

        record.applySummary(result)

        #expect(record.summaryText?.contains("Cleaned line") == true)
        #expect(record.summarySourceKind == SummarySourceKind.cleaned.rawValue)
    }
}

private struct MockTranscriptSummarizer: TranscriptSummarizing {
    let summaryText: String
    var availability: TranscriptCleanupAvailability = .available

    func summarize(
        lines: [String],
        sourceKind: SummarySourceKind,
        onProgress: ((TranscriptSummaryProgress) async -> Void)?
    ) async throws -> TranscriptSummaryResult {
        await onProgress?(
            TranscriptSummaryProgress(
                completedChunks: 1,
                totalChunks: 1,
                message: "Finished part 1 of 1"
            )
        )
        return TranscriptSummaryResult(
            summaryText: summaryText,
            sourceKind: sourceKind,
            promptVersion: "mock",
            generatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
