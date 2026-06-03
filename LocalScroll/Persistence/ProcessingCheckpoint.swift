import Foundation
import SwiftData

@Model
final class ProcessingCheckpoint {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var processingVideoFileName: String
    var preCachedVideoFileName: String?
    var qualityPreset: String
    var captionMode: Bool
    var cleanupEnabled: Bool
    var progressFraction: Double
    var lastTimestamp: Double
    var processedFrames: Int
    var sampleData: Data
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        processingVideoFileName: String,
        preCachedVideoFileName: String?,
        qualityPreset: QualityPreset,
        captionMode: Bool,
        cleanupEnabled: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.processingVideoFileName = processingVideoFileName
        self.preCachedVideoFileName = preCachedVideoFileName
        self.qualityPreset = qualityPreset.rawValue
        self.captionMode = captionMode
        self.cleanupEnabled = cleanupEnabled
        self.progressFraction = 0
        self.lastTimestamp = 0
        self.processedFrames = 0
        self.sampleData = Data()
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var decodedSamples: [PipelineFrameCheckpoint] {
        guard !sampleData.isEmpty,
              let samples = try? JSONDecoder().decode([PipelineFrameCheckpoint].self, from: sampleData) else {
            return []
        }
        return samples
    }

    func update(with snapshot: PipelineCheckpointSnapshot, progressFraction: Double) {
        lastTimestamp = snapshot.timestamp
        processedFrames = snapshot.processedFrames
        self.progressFraction = progressFraction
        sampleData = (try? JSONEncoder().encode(snapshot.baseSamples)) ?? sampleData
        updatedAt = Date()
    }
}
