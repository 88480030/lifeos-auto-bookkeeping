import ActivityKit
import Foundation

/// Small, shared payload used by the app and WidgetKit extension.
/// Countdown ticks are rendered by the system from dates; no per-second updates.
struct StudyActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var phase: String
        var phaseTitle: String
        var taskTitle: String
        var isPaused: Bool
        var remainingSeconds: Int
        var durationSeconds: Int
        var startAt: Date
        var endAt: Date
        var round: Int
        var rounds: Int
    }

    /// Stable for one focus and its following break; a new focus gets a new ID.
    var timerID: String
}
