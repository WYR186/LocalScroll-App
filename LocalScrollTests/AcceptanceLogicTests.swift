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
}
