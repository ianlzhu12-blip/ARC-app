import ActivityKit
import SwiftUI
import WidgetKit

struct LaunchTimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LaunchTimerActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Label("Launch Window", systemImage: iconName(for: context.state.stateRawValue))
                    .font(.headline)
                timerText(for: context.state)
                    .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                Text(statusText(for: context.state.stateRawValue))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.88))
            .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Launch", systemImage: iconName(for: context.state.stateRawValue))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timerText(for: context.state)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(statusText(for: context.state.stateRawValue))
                        .font(.caption)
                }
            } compactLeading: {
                Image(systemName: iconName(for: context.state.stateRawValue))
            } compactTrailing: {
                timerText(for: context.state)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }

    @ViewBuilder
    private func timerText(for state: LaunchTimerActivityAttributes.ContentState) -> some View {
        if state.stateRawValue == "running", let endsAt = state.endsAt, endsAt > .now {
            Text(timerInterval: Date.now...endsAt, countsDown: true)
        } else {
            Text(formattedTime(state.remainingSeconds))
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return "\(String(format: "%02d", clamped / 60)):\(String(format: "%02d", clamped % 60))"
    }

    private func iconName(for state: String) -> String {
        state == "paused" ? "pause.circle.fill" : "timer"
    }

    private func statusText(for state: String) -> String {
        switch state {
        case "running": return "Running"
        case "paused": return "Paused"
        default: return "Ready"
        }
    }
}

@main
struct ARCFlightOptimizerLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        LaunchTimerLiveActivityWidget()
    }
}
