import ActivityKit
import SwiftUI
import WidgetKit

struct ProcessingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProcessingActivityAttributes.self) { context in
            LockScreenProgressView(context: context)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityIcon(size: 28, iconSize: 13)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(percentText(context.state.progress))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText())
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text("LocalScroll")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(context.attributes.videoName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        ProgressBar(progress: context.state.progress)
                        HStack(spacing: 5) {
                            Image(systemName: "text.viewfinder")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Text(context.state.status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                ProgressRing(progress: context.state.progress)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
            } compactTrailing: {
                Text(percentText(context.state.progress))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProgressRing(progress: context.state.progress)
                    .frame(width: 44, height: 44)
                    .overlay {
                        ActivityIcon(size: 30, iconSize: 14)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.videoName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(context.state.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(percentText(context.state.progress))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText())
                    Text("LocalScroll")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            ProgressBar(progress: context.state.progress)
        }
        .padding(.vertical, 5)
    }
}

private struct ActivityIcon: View {
    let size: CGFloat
    let iconSize: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.14))
            Image(systemName: "text.viewfinder")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: size, height: size)
    }
}

private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.16))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor,
                                Color.accentColor.opacity(0.68),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, proxy.size.width * clamped))
            }
        }
        .frame(height: 5)
    }
}

private struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private func percentText(_ progress: Double) -> String {
    "\(Int((min(max(progress, 0), 1) * 100).rounded()))%"
}
