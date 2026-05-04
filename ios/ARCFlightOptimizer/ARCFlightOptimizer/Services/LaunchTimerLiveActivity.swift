import Foundation

#if canImport(ActivityKit)
import ActivityKit

enum LaunchTimerLiveActivity {
    private static var activity: Activity<LaunchTimerActivityAttributes>? {
        Activity<LaunchTimerActivityAttributes>.activities.first
    }

    static func update(state: LaunchTimerState, remainingSeconds: Int, endsAt: Date?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        Task {
            let content = ActivityContent(
                state: LaunchTimerActivityAttributes.ContentState(
                    stateRawValue: state.rawValue,
                    remainingSeconds: remainingSeconds,
                    endsAt: endsAt
                ),
                staleDate: endsAt
            )

            switch state {
            case .running:
                if let activity {
                    await activity.update(content)
                } else {
                    _ = try? Activity.request(
                        attributes: LaunchTimerActivityAttributes(title: "Launch Window"),
                        content: content,
                        pushType: nil
                    )
                }
            case .paused:
                if let activity {
                    await activity.update(content)
                }
            case .stopped:
                if let activity {
                    await activity.end(content, dismissalPolicy: .immediate)
                }
            }
        }
    }
}
#else
enum LaunchTimerLiveActivity {
    static func update(state: LaunchTimerState, remainingSeconds: Int, endsAt: Date?) {}
}
#endif
