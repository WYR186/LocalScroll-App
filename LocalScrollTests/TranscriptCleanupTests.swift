import Foundation
import LocalScrollCore
import Testing
@testable import LocalScroll

struct TranscriptCleanupTests {
    @Test func repeatedCompleteSentenceCollapseKeepsUniqueContent() {
        let lines = [
            "Welcome to the meeting.",
            "Welcome to the meeting.",
            "Today we will review LocalScroll.",
            "Next we will discuss the roadmap.",
            "Next we will discuss the roadmap.",
            "Thanks everyone",
            "Thanks everyone",
        ]

        let cleaned = FoundationModelTranscriptCleaner.collapseRepeatedCompleteSentences(lines)

        #expect(cleaned == [
            "Welcome to the meeting.",
            "Today we will review LocalScroll.",
            "Next we will discuss the roadmap.",
            "Thanks everyone",
            "Thanks everyone",
        ])
    }

    @Test func cleanupResultRetainsRawTranscript() {
        let raw = Transcript(
            lines: [
                "The release starts today.",
                "The release starts today.",
                "Questions are welcome.",
            ],
            sourceVideo: URL(fileURLWithPath: "/tmp/source.mov")
        )
        var cleaned = raw
        cleaned.lines = FoundationModelTranscriptCleaner.collapseRepeatedCompleteSentences(raw.lines)

        let result = TranscriptCleanupResult(rawTranscript: raw, cleanedTranscript: cleaned)

        #expect(result.rawTranscript == raw)
        #expect(result.cleanedTranscript.lines == [
            "The release starts today.",
            "Questions are welcome.",
        ])
        #expect(result.didChange)
    }

    @Test func conservativeModelResponseFallsBackWhenOutputIsUnrelated() {
        let rawLines = [
            "Alpha shipped successfully.",
            "Alpha shipped successfully.",
            "Beta is still pending.",
        ]

        let cleaned = FoundationModelTranscriptCleaner.conservativeLines(
            from: "A completely unrelated summary.",
            rawLines: rawLines,
            threshold: 92
        )

        #expect(cleaned == [
            "Alpha shipped successfully.",
            "Beta is still pending.",
        ])
    }
}
