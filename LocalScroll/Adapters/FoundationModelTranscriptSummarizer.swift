import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum SummarySourceKind: String, Codable, Equatable, Sendable {
    case raw
    case cleaned

    var title: String {
        switch self {
        case .raw: return "Raw"
        case .cleaned: return "Cleaned"
        }
    }
}

enum SummaryGenerationMode: String, CaseIterable, Identifiable {
    case manual
    case afterProcessing
    case withCleanup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Manual"
        case .afterProcessing: return "After Processing"
        case .withCleanup: return "With AI Cleanup"
        }
    }

    var detail: String {
        switch self {
        case .manual:
            return "Generate summaries from History when needed."
        case .afterProcessing:
            return "Generate summaries automatically after each finished extraction."
        case .withCleanup:
            return "Generate summaries automatically only for items processed with AI Cleanup."
        }
    }

    func shouldGenerateAfterProcessing(cleanupEnabled: Bool) -> Bool {
        switch self {
        case .manual:
            return false
        case .afterProcessing:
            return true
        case .withCleanup:
            return cleanupEnabled
        }
    }
}

struct TranscriptSummaryChunk: Equatable, Sendable {
    let index: Int
    let startLine: Int
    let endLine: Int
    let lines: [String]
    let estimatedTokens: Int

    var numberedText: String {
        lines.enumerated()
            .map { offset, line in
                "\(startLine + offset). \(line)"
            }
            .joined(separator: "\n")
    }
}

struct TranscriptSummaryProgress: Equatable, Sendable {
    let completedChunks: Int
    let totalChunks: Int
    let message: String

    var fractionCompleted: Double {
        guard totalChunks > 0 else { return 0 }
        return min(1, Double(completedChunks) / Double(totalChunks))
    }
}

struct TranscriptSummaryResult: Equatable, Sendable {
    let summaryText: String
    let sourceKind: SummarySourceKind
    let promptVersion: String
    let generatedAt: Date
}

enum FoundationModelTranscriptSummarizerError: Error, LocalizedError, Equatable {
    case unavailable(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        case .emptyTranscript:
            return "There is no transcript text to summarize."
        }
    }
}

protocol TranscriptSummarizing {
    var availability: TranscriptCleanupAvailability { get }

    func summarize(
        lines: [String],
        sourceKind: SummarySourceKind,
        onProgress: ((TranscriptSummaryProgress) async -> Void)?
    ) async throws -> TranscriptSummaryResult
}

final class FoundationModelTranscriptSummarizer: TranscriptSummarizing {
    static let promptVersion = "history-summary-v1"
    static let defaultMaxEstimatedTokensPerChunk = 1_600

    var availability: TranscriptCleanupAvailability {
        Self.currentAvailability
    }

    static var currentAvailability: TranscriptCleanupAvailability {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                return .unavailable("Foundation Models unavailable: \(reason)")
            @unknown default:
                return .unavailable("Foundation Models unavailable on this device.")
            }
        }
#endif
        return .unavailable("Foundation Models summary requires iOS 26.")
    }

    static var isSupportedOnCurrentOS: Bool {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return true
        }
#endif
        return false
    }

    static var availabilityMessage: String {
        switch currentAvailability {
        case .available:
            return "Foundation Models summary is available."
        case .unavailable(let reason):
            return reason
        }
    }

    func summarize(
        lines: [String],
        sourceKind: SummarySourceKind,
        onProgress: ((TranscriptSummaryProgress) async -> Void)? = nil
    ) async throws -> TranscriptSummaryResult {
        guard case .available = availability else {
            throw FoundationModelTranscriptSummarizerError.unavailable(Self.availabilityMessage)
        }

        let normalizedLines = Self.normalizedLines(lines)
        guard !normalizedLines.isEmpty else {
            throw FoundationModelTranscriptSummarizerError.emptyTranscript
        }

#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await summarizeWithFoundationModels(
                normalizedLines,
                sourceKind: sourceKind,
                onProgress: onProgress
            )
        }
#endif

        throw FoundationModelTranscriptSummarizerError.unavailable(Self.availabilityMessage)
    }

    static func normalizedLines(_ lines: [String]) -> [String] {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func sourceLines(rawLines: [String], cleanedLines: [String]?) -> (SummarySourceKind, [String]) {
        if let cleaned = cleanedLines, !normalizedLines(cleaned).isEmpty {
            return (.cleaned, cleaned)
        }
        return (.raw, rawLines)
    }

    static func chunks(
        for lines: [String],
        maxEstimatedTokens: Int = defaultMaxEstimatedTokensPerChunk
    ) -> [TranscriptSummaryChunk] {
        let normalized = normalizedLines(lines)
        guard !normalized.isEmpty else { return [] }

        let tokenLimit = max(200, maxEstimatedTokens)
        var chunks: [TranscriptSummaryChunk] = []
        var currentLines: [String] = []
        var currentTokens = 0
        var currentStartLine = 1

        func flush(endLine: Int) {
            guard !currentLines.isEmpty else { return }
            chunks.append(
                TranscriptSummaryChunk(
                    index: chunks.count + 1,
                    startLine: currentStartLine,
                    endLine: endLine,
                    lines: currentLines,
                    estimatedTokens: currentTokens
                )
            )
            currentLines = []
            currentTokens = 0
        }

        for (offset, line) in normalized.enumerated() {
            let lineNumber = offset + 1
            let lineTokens = estimatedTokenCount(line)
            if !currentLines.isEmpty, currentTokens + lineTokens > tokenLimit {
                flush(endLine: lineNumber - 1)
                currentStartLine = lineNumber
            }

            currentLines.append(line)
            currentTokens += lineTokens
        }

        flush(endLine: normalized.count)
        return chunks
    }

    static func estimatedTokenCount(_ text: String) -> Int {
        let scalarCount = text.unicodeScalars.count
        guard scalarCount > 0 else { return 0 }

        let cjkCount = text.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3040...0x30FF, 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }.count
        let nonCJKCount = scalarCount - cjkCount
        let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
        let characterEstimate = Int(ceil(Double(nonCJKCount) / 4.0 + Double(cjkCount) * 0.8))
        return max(1, wordCount, characterEstimate)
    }

    static func cleanedModelText(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty && line != "```" && !line.hasPrefix("```")
            }

        return lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func finalSummaryText(
        from chunkSummaries: [String],
        sourceKind: SummarySourceKind,
        totalLines: Int
    ) -> String {
        guard !chunkSummaries.isEmpty else { return "" }

        var sections = [
            "# Detailed Summary",
            "",
            "Source: \(sourceKind.title) transcript",
            "Covered transcript lines: \(totalLines)",
            "",
        ]

        for (index, summary) in chunkSummaries.enumerated() {
            sections.append("## Part \(index + 1)")
            sections.append(summary)
            if index < chunkSummaries.count - 1 {
                sections.append("")
            }
        }

        return sections.joined(separator: "\n")
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func summarizeWithFoundationModels(
        _ lines: [String],
        sourceKind: SummarySourceKind,
        onProgress: ((TranscriptSummaryProgress) async -> Void)?
    ) async throws -> TranscriptSummaryResult {
        let chunks = Self.chunks(for: lines)
        var chunkSummaries: [String] = []
        chunkSummaries.reserveCapacity(chunks.count)

        for chunk in chunks {
            try Task.checkCancellation()
            await onProgress?(
                TranscriptSummaryProgress(
                    completedChunks: chunk.index - 1,
                    totalChunks: chunks.count,
                    message: "Summarizing part \(chunk.index) of \(chunks.count)..."
                )
            )

            let summary = try await summarize(chunk: chunk, totalChunks: chunks.count)
            let repaired = try await repair(summary: summary, for: chunk)
            let chunkText = Self.cleanedModelText(repaired).isEmpty ? summary : repaired
            chunkSummaries.append(Self.cleanedModelText(chunkText))

            await onProgress?(
                TranscriptSummaryProgress(
                    completedChunks: chunk.index,
                    totalChunks: chunks.count,
                    message: "Finished part \(chunk.index) of \(chunks.count)"
                )
            )
        }

        let summaryText = Self.finalSummaryText(
            from: chunkSummaries,
            sourceKind: sourceKind,
            totalLines: lines.count
        )

        return TranscriptSummaryResult(
            summaryText: summaryText,
            sourceKind: sourceKind,
            promptVersion: Self.promptVersion,
            generatedAt: Date()
        )
    }

    @available(iOS 26.0, *)
    private func summarize(chunk: TranscriptSummaryChunk, totalChunks: Int) async throws -> String {
        let instructions = """
        You create detailed outlines from OCR transcripts.
        Use only the provided transcript lines.
        Preserve every concrete piece of information: names, dates, numbers, decisions, tasks, warnings, commands, code, file names, URLs, and examples.
        Keep the original order. Do not translate. Do not invent context.
        It is acceptable for the summary to be long.
        Return plain Markdown bullets and short headings only.
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: Self.summaryPrompt(for: chunk, totalChunks: totalChunks))
        return Self.cleanedModelText(response.content)
    }

    @available(iOS 26.0, *)
    private func repair(summary: String, for chunk: TranscriptSummaryChunk) async throws -> String {
        let instructions = """
        You repair a draft summary by checking it against the original OCR transcript lines.
        Keep the draft content, then append any missing concrete facts from the source.
        Do not remove details. Do not add facts not present in the source.
        Return only the repaired detailed Markdown outline.
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: Self.repairPrompt(for: chunk, draft: summary))
        let repaired = Self.cleanedModelText(response.content)
        return repaired.isEmpty ? summary : repaired
    }

    private static func summaryPrompt(for chunk: TranscriptSummaryChunk, totalChunks: Int) -> String {
        """
        Summarize transcript part \(chunk.index) of \(totalChunks).
        Line range: \(chunk.startLine)-\(chunk.endLine).
        Produce a detailed outline that preserves all information and keeps the source order.

        Transcript:
        \(chunk.numberedText)
        """
    }

    private static func repairPrompt(for chunk: TranscriptSummaryChunk, draft: String) -> String {
        """
        Original transcript lines \(chunk.startLine)-\(chunk.endLine):
        \(chunk.numberedText)

        Draft summary:
        \(draft)

        Repair the draft so no concrete information from the original lines is missing.
        """
    }
#endif
}
