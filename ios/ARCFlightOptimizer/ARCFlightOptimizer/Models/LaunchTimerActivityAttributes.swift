import Foundation

#if canImport(ActivityKit)
import ActivityKit

struct LaunchTimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var stateRawValue: String
        var remainingSeconds: Int
        var endsAt: Date?
    }

    var title: String
}
#endif
