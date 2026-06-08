import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Presentation model

private extension ProcessingPhase {
    var isActive: Bool {
        switch self {
        case .done, .paused, .failed: return false
        default: return true
        }
    }

    /// SF Symbol shown inside the phase badge / status chips.
    var symbol: String {
        switch self {
        case .importing:   return "square.and.arrow.down"
        case .preparing:   return "film.stack"
        case .extracting:  return "text.viewfinder"
        case .cleaning:    return "sparkles"
        case .summarizing: return "list.bullet.rectangle"
        case .saving:      return "tray.and.arrow.down"
        case .done:        return "checkmark"
        case .paused:      return "pause.fill"
        case .failed:      return "exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .done:   return .green
        case .failed: return .orange
        case .paused: return .secondary
        default:      return .accentColor
        }
    }

    /// Friendly status verb.
    var verb: String {
        switch self {
        case .importing:   return "Importing"
        case .preparing:   return "Preparing"
        case .extracting:  return "Extracting text"
        case .cleaning:    return "Cleaning up"
        case .summarizing: return "Summarizing"
        case .saving:      return "Saving"
        case .done:        return "Done"
        case .paused:      return "Paused"
        case .failed:      return "Couldn’t finish"
        }
    }
}

private extension ProcessingActivityAttributes.ContentState {
    /// Primary status line.
    var headline: String {
        if phase == .failed, let detail, !detail.isEmpty { return detail }
        return phase.verb
    }

    /// Small secondary clause, e.g. "38 lines". `nil` when there is nothing useful to add.
    var subtitle: String? {
        switch phase {
        case .paused:
            return detail ?? "Progress saved"
        case .failed:
            return nil                       // reason already promoted to headline
        case .done:
            return Self.linesText(lineCount)
        default:
            return lineCount > 0 ? Self.linesText(lineCount) : detail
        }
    }

    static func linesText(_ count: Int) -> String {
        count == 1 ? "1 line" : "\(count) lines"
    }
}

// MARK: - Widget

struct ProcessingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProcessingActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(nil)                 // default system material — adapts to light/dark
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseBadge(state: state, diameter: 34)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TrailingStatus(state: state, font: .callout, showsBrand: false)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.videoName)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(state.headline)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 7) {
                        PhaseProgressBar(state: state)
                        HStack(spacing: 4) {
                            if let subtitle = state.subtitle {
                                Text(subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Text("LocalScroll")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } compactLeading: {
                PhaseBadge(state: state, diameter: 22, iconScale: 0.42)
            } compactTrailing: {
                TrailingStatus(state: state, font: .caption2, showsBrand: false, compact: true)
            } minimal: {
                PhaseBadge(state: state, diameter: 22, iconScale: 0.42)
            }
            .keylineTint(state.phase.tint)
        }
    }
}

// MARK: - Lock screen

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<ProcessingActivityAttributes>

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PhaseBadge(state: state, diameter: 44, iconScale: 0.4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.videoName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 5) {
                        Text(state.headline)
                        if let subtitle = state.subtitle {
                            Text("·").foregroundStyle(.tertiary)
                            Text(subtitle)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                TrailingStatus(state: state, font: .title3, showsBrand: true)
            }

            PhaseProgressBar(state: state)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }
}

// MARK: - Shared pieces

/// Tinted circle holding the phase symbol. While active the ring traces
/// progress; when terminal it shows a calm, fully drawn ring.
private struct PhaseBadge: View {
    let state: ProcessingActivityAttributes.ContentState
    var diameter: CGFloat
    var iconScale: CGFloat = 0.46

    var body: some View {
        let tint = state.phase.tint
        let lineWidth = max(2, diameter * 0.09)
        ZStack {
            Circle().fill(tint.opacity(0.16))

            if state.phase.isActive {
                Circle()
                    .stroke(tint.opacity(0.22), lineWidth: lineWidth)
                    .padding(lineWidth / 2)
                Circle()
                    .trim(from: 0, to: clampFraction(state.progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth / 2)
            } else {
                Circle()
                    .stroke(tint.opacity(0.35), lineWidth: lineWidth)
                    .padding(lineWidth / 2)
            }

            Image(systemName: state.phase.symbol)
                .font(.system(size: diameter * iconScale, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Trailing percent (while active) or the terminal phase glyph, with an optional
/// "LocalScroll" brand line beneath.
private struct TrailingStatus: View {
    let state: ProcessingActivityAttributes.ContentState
    var font: Font
    var showsBrand: Bool
    var compact: Bool = false

    var body: some View {
        let tint = state.phase.tint
        VStack(alignment: .trailing, spacing: 1) {
            if state.phase.isActive {
                Text(percentText(state.progress))
                    .font(font.monospacedDigit().weight(.semibold))
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
            } else {
                Image(systemName: state.phase.symbol)
                    .font(font.weight(.bold))
                    .foregroundStyle(tint)
            }

            if showsBrand {
                Text("LocalScroll")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(compact ? tint : .primary)
    }
}

/// Rounded capsule track with a tinted, gradient fill. Reads full + green on `.done`.
private struct PhaseProgressBar: View {
    let state: ProcessingActivityAttributes.ContentState

    var body: some View {
        let tint = state.phase.tint
        GeometryReader { proxy in
            let width = proxy.size.width
            let fill = state.phase == .done ? width : max(4, width * clampFraction(state.progress))
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.16))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fill)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Helpers

private func clampFraction(_ x: Double) -> Double { min(max(x, 0), 1) }

private func percentText(_ progress: Double) -> String {
    "\(Int((clampFraction(progress) * 100).rounded()))%"
}

// MARK: - Previews
//
// Live Activities do not render in the simulator, so these previews let the
// redesign be checked in the Xcode canvas across every phase without a device.

private typealias PreviewState = ProcessingActivityAttributes.ContentState

private let previewAttributes = ProcessingActivityAttributes(videoName: "Lecture 4 — Fallacies.mov")

private let previewExtracting = PreviewState(progress: 0.62, phase: .extracting, lineCount: 38, detail: nil)
private let previewSummarizing = PreviewState(progress: 1, phase: .summarizing, lineCount: 38, detail: nil)
private let previewDone = PreviewState(progress: 1, phase: .done, lineCount: 38, detail: nil)
private let previewPaused = PreviewState(progress: 0.43, phase: .paused, lineCount: 0, detail: "Progress saved")
private let previewFailed = PreviewState(progress: 0.21, phase: .failed, lineCount: 0, detail: "Not enough disk space")

#Preview("Lock Screen", as: .content, using: previewAttributes) {
    ProcessingLiveActivityWidget()
} contentStates: {
    previewExtracting
    previewSummarizing
    previewDone
    previewPaused
    previewFailed
}

#Preview("Dynamic Island (expanded)", as: .dynamicIsland(.expanded), using: previewAttributes) {
    ProcessingLiveActivityWidget()
} contentStates: {
    previewExtracting
    previewDone
    previewPaused
    previewFailed
}

#Preview("Dynamic Island (compact)", as: .dynamicIsland(.compact), using: previewAttributes) {
    ProcessingLiveActivityWidget()
} contentStates: {
    previewExtracting
    previewDone
    previewFailed
}

#Preview("Dynamic Island (minimal)", as: .dynamicIsland(.minimal), using: previewAttributes) {
    ProcessingLiveActivityWidget()
} contentStates: {
    previewExtracting
    previewDone
    previewPaused
}
