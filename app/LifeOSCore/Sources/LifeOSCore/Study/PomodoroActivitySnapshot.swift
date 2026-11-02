import Foundation

/// A timestamp-based presentation of the actual machine, shared by all activity states.
public struct PomodoroActivitySnapshot: Equatable, Sendable {
    public let timerID: String
    public let phase: String
    public let phaseTitle: String
    public let taskTitle: String
    public let isPaused: Bool
    public let remainingSeconds: Int
    public let durationSeconds: Int
    public let startAt: Date
    public let endAt: Date
    public let round: Int
    public let rounds: Int

    public init?(machine: PomodoroMachine, timerID: String, now: Date = .now) {
        guard !machine.isIdle else { return nil }
        self.timerID = timerID
        phase = machine.phase.rawValue
        phaseTitle = machine.phase.displayName
        taskTitle = String((machine.taskTitle ?? "").prefix(80))
        isPaused = machine.isPaused
        remainingSeconds = machine.remainingSeconds(now: now)
        durationSeconds = machine.phaseDurationSeconds
        endAt = machine.phaseEndAt ?? now.addingTimeInterval(TimeInterval(remainingSeconds))
        // After a pause the original phaseStartedAt includes time spent paused.
        // Derive the visual progress interval from the actual end timestamp instead.
        startAt = endAt.addingTimeInterval(-TimeInterval(durationSeconds))
        rounds = max(1, machine.configuration.longBreakEvery)
        let completed = machine.completedFocusSessions
        round = machine.phase == .focus ? completed % rounds + 1 : max(0, completed - 1) % rounds + 1
    }

    /// A delayed or repeated action targets the expected phase and desired state.
    public static func acceptsAction(machine: PomodoroMachine, currentTimerID: String, requestedTimerID: String,
                                     phase: String, resume: Bool, now: Date = .now) -> Bool {
        guard !machine.isIdle, currentTimerID == requestedTimerID,
              machine.phase.rawValue == phase else { return false }
        if resume { return machine.isPaused }
        return machine.isRunning && (machine.phaseEndAt ?? .distantPast) > now
    }
}
