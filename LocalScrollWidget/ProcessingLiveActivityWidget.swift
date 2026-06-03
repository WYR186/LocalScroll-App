import ActivityKit
import SwiftUI
import WidgetKit

struct ProcessingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProcessingActivityAttributes.self) { context in
            LockScreenProgressView(context: context)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("LocalScroll", systemImage: "text.viewfinder")
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(percentText(context.state.progress))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressBar(progress: context.state.progress)
                        Text(context.state.status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "text.viewfinder")
            } compactTrailing: {
                Text(percentText(context.state.progress))
                    .font(.caption2.monospacedDigit())
                    .minimumScaleFactor(0.8)
            } minimal: {
                ProgressRing(progress: context.state.progress)
                    .frame(width: 20, height: 20)
            }
        }
    }
}

private struct LockScreenProgressView: View {
    let context: ActivityViewContext<ProcessingActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "text.viewfinder")
                    .foregroundStyle(Color.accentColor)
                Text(context.attributes.videoName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(percentText(context.state.progress))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressBar(progress: context.state.progress)

            Text(context.state.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.22))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(4, proxy.size.width * clamped))
            }
        }
        .frame(height: 6)
    }
}

private struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.28), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private func percentText(_ progress: Double) -> String {
    "\(Int((min(max(progress, 0), 1) * 100).rounded()))%"
}
