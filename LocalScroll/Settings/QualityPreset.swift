import Foundation
import LocalScrollCore

public enum QualityPreset: String, CaseIterable, Identifiable {
    case fast
    case smart
    case precise

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fast: return "Fast"
        case .smart: return "Smart"
        case .precise: return "Precise"
        }
    }

    public var fps: Double {
        switch self {
        case .fast: return 2
        case .smart: return 6
        case .precise: return 8
        }
    }

    public var usesAdaptiveSampling: Bool {
        switch self {
        case .fast, .precise: return false
        case .smart: return true
        }
    }

    public var usesPreprocessing: Bool {
        switch self {
        case .fast: return false
        case .smart, .precise: return true
        }
    }

    public var stitchConfig: StitchConfig {
        switch self {
        case .fast:
            return StitchConfig(tailSize: 15, minConfidence: 0.5)
        case .smart:
            return StitchConfig(tailSize: 30, minConfidence: 0.4)
        case .precise:
            return StitchConfig(tailSize: 30, minConfidence: 0.45)
        }
    }

    public var schedulerConfig: SchedulerConfig {
        switch self {
        case .fast, .precise:
            return SchedulerConfig()
        case .smart:
            return SchedulerConfig(commitReverse: true)
        }
    }
}
