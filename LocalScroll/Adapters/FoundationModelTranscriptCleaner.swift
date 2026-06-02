import Foundation
import LocalScrollCore

#if canImport(FoundationModels)
import FoundationModels
#endif

public enum FoundationModelTranscriptCleanerError: Error, LocalizedError, Equatable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        }
    }
}

public final class FoundationModelTranscriptCleaner: TranscriptCleaner {
    private let similarityThreshold: Int

    public init(similarityThreshold: Int = 92) {
        self.similarityThreshold = similarityThreshold
    }

    public var availability: TranscriptCleanupAvailability {
        Self.currentAvailability
    }

    public static var currentAvailability: TranscriptCleanupAvailability {
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
        return .unavailable("Foundation Models cleanup requires iOS 26.")
    }

    public static var isSupportedOnCurrentOS: Bool {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return true
        }
#endif
        return false
    }

    public func cleanup(_ transcript: LocalScrollCore.Transcript) async throws -> TranscriptCleanupResult {
        guard case .available = availability else {
            throw FoundationModelTranscriptCleanerError.unavailable(Self.availabilityMessage)
        }

#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await cleanupWithFoundationModels(transcript)
        }
#endif

        throw FoundationModelTranscriptCleanerError.unavailable(Self.availabilityMessage)
    }

    static var availabilityMessage: String {
        switch currentAvailability {
        case .available:
            return "Foundation Models cleanup is available."
        case .unavailable(let reason):
            return reason
        }
    }

    static func collapseRepeatedCompleteSentences(
        _ lines: [String],
        threshold: Int = 92
    ) -> [String] {
        var cleaned: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if isCompleteSentence(trimmed),
               let previous = cleaned.last,
               isCompleteSentence(previous),
               similar(trimmed, previous, threshold: threshold) {
                continue
            }

            cleaned.append(trimmed)
        }

        return cleaned
    }

    static func conservativeLines(from response: String, rawLines: [String], threshold: Int) -> [String] {
        let proposedLines = parseResponseLines(response)
        guard !proposedLines.isEmpty else {
            return collapseRepeatedCompleteSentences(rawLines, threshold: threshold)
        }

        var accepted: [String] = []
        var searchStart = rawLines.startIndex

        for proposed in proposedLines {
            guard searchStart < rawLines.endIndex else { break }

            if let match = rawLines[searchStart...].firstIndex(where: { similar(proposed, $0, threshold: 70) }) {
                accepted.append(proposed)
                searchStart = rawLines.index(after: match)
            }
        }

        guard !accepted.isEmpty else {
            return collapseRepeatedCompleteSentences(rawLines, threshold: threshold)
        }

        return collapseRepeatedCompleteSentences(accepted, threshold: threshold)
    }

    private static func parseResponseLines(_ response: String) -> [String] {
        response
            .components(separatedBy: .newlines)
            .map { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty && line != "```" && !line.hasPrefix("```")
            }
            .map { line in
                line.replacingOccurrences(
                    of: #"^\s*(?:[-*]|\d+[.)])\s*"#,
                    with: "",
                    options: .regularExpression
                )
            }
            .map { line in
                line.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private static func isCompleteSentence(_ line: String) -> Bool {
        guard let last = line.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return [".", "!", "?", "。", "！", "？"].contains(last)
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func cleanupWithFoundationModels(
        _ transcript: LocalScrollCore.Transcript
    ) async throws -> TranscriptCleanupResult {
        let rawLines = transcript.lines
        guard !rawLines.isEmpty else {
            return TranscriptCleanupResult(rawTranscript: transcript, cleanedTranscript: transcript)
        }

        let instructions = """
        You clean OCR transcripts from screen-recorded or Zoom-style videos.
        Work only on the provided transcript lines.
        Remove repeated complete sentences caused by the same spoken sentence being captured across frames.
        Preserve order and every unique piece of content.
        Do not summarize, add facts, translate, or rewrite meaning.
        Return only plain text, one transcript line per line.
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: Self.prompt(for: rawLines))
        let cleanedLines = Self.conservativeLines(
            from: response.content,
            rawLines: rawLines,
            threshold: similarityThreshold
        )

        var cleanedTranscript = transcript
        cleanedTranscript.lines = cleanedLines
        return TranscriptCleanupResult(rawTranscript: transcript, cleanedTranscript: cleanedTranscript)
    }

    private static func prompt(for lines: [String]) -> String {
        let numberedLines = lines.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        return """
        Clean this transcript. Keep unique content and order. Output only cleaned transcript lines.

        \(numberedLines)
        """
    }
#endif
}
