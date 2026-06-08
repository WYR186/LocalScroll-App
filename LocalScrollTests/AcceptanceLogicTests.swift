import Foundation
import SwiftUI
import Testing
@testable import LocalScroll

struct AcceptanceLogicTests {
    @Test func qualityPresetsMatchAcceptanceSamplingContract() {
        #expect(QualityPreset.fast.fps == 2)
        #expect(!QualityPreset.fast.usesAdaptiveSampling)
        #expect(QualityPreset.fast.coverageRefinementConfig.refinementFPS == 6)

        #expect(QualityPreset.smart.fps == 6)
        #expect(QualityPreset.smart.usesAdaptiveSampling)
        #expect(QualityPreset.smart.usesPreprocessing)
        #expect(QualityPreset.smart.schedulerConfig.commitReverse)

        #expect(QualityPreset.precise.fps == 8)
        #expect(!QualityPreset.precise.usesAdaptiveSampling)
        #expect(QualityPreset.precise.usesPreprocessing)
        #expect(QualityPreset.precise.coverageRefinementConfig.refinementFPS == 12)
        #expect(QualityPreset.precise.coverageRefinementConfig.lineDropRatio == 0.65)
    }

    @Test func ocrLanguagePreferencesMapToVisionSettings() {
        #expect(OCRLanguagePreference.automatic.recognitionLanguages.isEmpty)
        #expect(OCRLanguagePreference.automatic.automaticallyDetectsLanguage)

        #expect(OCRLanguagePreference.english.recognitionLanguages == ["en-US"])
        #expect(!OCRLanguagePreference.english.automaticallyDetectsLanguage)

        #expect(OCRLanguagePreference.simplifiedChinese.recognitionLanguages == ["zh-Hans"])
        #expect(!OCRLanguagePreference.simplifiedChinese.automaticallyDetectsLanguage)

        #expect(OCRLanguagePreference.traditionalChinese.recognitionLanguages == ["zh-Hant"])
        #expect(!OCRLanguagePreference.traditionalChinese.automaticallyDetectsLanguage)
    }

    @Test func appearancePreferencesResolveExpectedColorSchemes() {
        #expect(AppearancePreference.system.colorScheme == nil)
        #expect(AppearancePreference.light.colorScheme == .light)
        #expect(AppearancePreference.dark.colorScheme == .dark)
    }

    @Test func duplicateVideoHistoryRecordsRemainIndependent() {
        let first = HistoryRecord(
            fileName: "IMG_0249",
            originalFileName: "IMG_0249.MOV",
            durationSeconds: 12,
            thumbnailData: Data([1]),
            rawLines: ["First run"],
            cleanedLines: nil,
            preferredCleaned: false,
            qualityPreset: QualityPreset.fast.rawValue,
            captionMode: false
        )
        let second = HistoryRecord(
            fileName: "IMG_0249",
            originalFileName: "IMG_0249.MOV",
            durationSeconds: 12,
            thumbnailData: Data([2]),
            rawLines: ["Second run"],
            cleanedLines: nil,
            preferredCleaned: false,
            qualityPreset: QualityPreset.fast.rawValue,
            captionMode: false
        )

        first.fileName = "First renamed"

        #expect(first.id != second.id)
        #expect(first.fileName == "First renamed")
        #expect(second.fileName == "IMG_0249")
        #expect(first.displayLines == ["First run"])
        #expect(second.displayLines == ["Second run"])
    }

    // MARK: - History search + preset filter

    private func makeRecord(
        fileName: String,
        originalFileName: String,
        preset: QualityPreset
    ) -> HistoryRecord {
        HistoryRecord(
            fileName: fileName,
            originalFileName: originalFileName,
            durationSeconds: 10,
            thumbnailData: Data([0]),
            rawLines: ["line"],
            cleanedLines: nil,
            preferredCleaned: false,
            qualityPreset: preset.rawValue,
            captionMode: false
        )
    }

    @Test func historySearchMatchesEditableTitleAndOriginalNameCaseInsensitively() {
        let renamed = makeRecord(fileName: "Lecture Notes", originalFileName: "IMG_0249.MOV", preset: .fast)
        let other = makeRecord(fileName: "Recipe", originalFileName: "IMG_8888.MOV", preset: .smart)
        let records = [renamed, other]

        // Matches the editable title (case-insensitive).
        #expect(HistoryFilter.apply(to: records, query: "lecture", preset: nil).map(\.id) == [renamed.id])
        // Matches the original file name even after the title was renamed.
        #expect(HistoryFilter.apply(to: records, query: "img_0249", preset: nil).map(\.id) == [renamed.id])
        // No match → empty.
        #expect(HistoryFilter.apply(to: records, query: "zzz", preset: nil).isEmpty)
    }

    @Test func historyBlankQueryReturnsEverythingAndTrimsWhitespace() {
        let records = [
            makeRecord(fileName: "A", originalFileName: "a.mov", preset: .fast),
            makeRecord(fileName: "B", originalFileName: "b.mov", preset: .smart),
        ]
        #expect(HistoryFilter.apply(to: records, query: "", preset: nil).count == 2)
        #expect(HistoryFilter.apply(to: records, query: "   ", preset: nil).count == 2)
    }

    @Test func historyPresetFilterExcludesOtherPresets() {
        let fast = makeRecord(fileName: "Fast clip", originalFileName: "f.mov", preset: .fast)
        let smart = makeRecord(fileName: "Smart clip", originalFileName: "s.mov", preset: .smart)
        let precise = makeRecord(fileName: "Precise clip", originalFileName: "p.mov", preset: .precise)
        let records = [fast, smart, precise]

        #expect(HistoryFilter.apply(to: records, query: "", preset: .smart).map(\.id) == [smart.id])
        // Search + preset combine (AND): query matches all "clip", preset narrows to precise.
        #expect(HistoryFilter.apply(to: records, query: "clip", preset: .precise).map(\.id) == [precise.id])
        // Preset matches but query does not → empty.
        #expect(HistoryFilter.apply(to: records, query: "fast", preset: .smart).isEmpty)
    }
}
