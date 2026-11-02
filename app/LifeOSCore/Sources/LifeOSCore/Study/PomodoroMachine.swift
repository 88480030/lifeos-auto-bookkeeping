import Foundation

// MARK: - Configuration

public struct PomodoroConfiguration: Codable, Sendable, Hashable {
    public var focusSeconds: Int
    public var shortBreakSeconds: Int
    public var longBreakSeconds: Int
    public var longBreakEvery: Int

    public init(
        focusMinutes: Int = 25,
        shortBreakMinutes: Int = 5,
        longBreakMinutes: Int = 15,
        longBreakEvery: Int = 4
    ) {
        self.focusSeconds = max(1, focusMinutes) * 60
        self.shortBreakSeconds = max(1, shortBreakMinutes) * 60
        self.longBreakSeconds = max(1, longBreakMinutes) * 60
        self.longBreakEvery = max(1, longBreakEvery)
    }

    public var focusMinutes: Int { focusSeconds / 60 }
    public var shortBreakMinutes: Int { shortBreakSeconds / 60 }
    public var longBreakMinutes: Int { longBreakSeconds / 60 }
}

public enum PomodoroPhase: String, Codable, Sendable {
    case focus
    case shortBreak
    case longBreak

    public var displayName: String {
        switch self {
        case .focus: "专注"
        case .shortBreak: "短休息"
        case .longBreak: "长休息"
        }
    }
}

public enum PomodoroRunState: String, Codable, Sendable {
    case idle
    case running
    case paused
}

public struct CompletedFocus: Codable, Sendable, Hashable {
    public var sessionID: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var focusedSeconds: Int
    public var taskTitle: String?
    public var subject: String?

    public init(
        sessionID: UUID,
        startedAt: Date,
        endedAt: Date,
        focusedSeconds: Int,
        taskTitle: String?,
        subject: String?
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.focusedSeconds = max(0, focusedSeconds)
        self.taskTitle = taskTitle
        self.subject = subject
    }
}

public enum PomodoroEvent: Sendable {
    case focusCompleted(CompletedFocus)
    case focusEndedEarly(CompletedFocus)
    case breakCompleted(wasLongBreak: Bool)
    case breakEnded
}

// MARK: - Machine

/// 基于时间戳的番茄钟状态机。暂停、后台恢复、提前结束都只依赖 Date。
public struct PomodoroMachine: Codable, Sendable {
    public private(set) var configuration: PomodoroConfiguration
    public private(set) var phase: PomodoroPhase
    public private(set) var state: PomodoroRunState
    public private(set) var sessionID: UUID?
    public private(set) var phaseStartedAt: Date?
    public private(set) var phaseEndAt: Date?
    public private(set) var pausedRemainingSeconds: Int?
    public private(set) var completedFocusSessions: Int
    public private(set) var taskTitle: String?
    public private(set) var subject: String?

    public init(configuration: PomodoroConfiguration = PomodoroConfiguration()) {
        self.configuration = configuration
        self.phase = .focus
        self.state = .idle
        self.sessionID = nil
        self.phaseStartedAt = nil
        self.phaseEndAt = nil
        self.pausedRemainingSeconds = nil
        self.completedFocusSessions = 0
        self.taskTitle = nil
        self.subject = nil
    }

    public var isIdle: Bool { state == .idle }
    public var isRunning: Bool { state == .running }
    public var isPaused: Bool { state == .paused }

    public var phaseDurationSeconds: Int {
        switch phase {
        case .focus: configuration.focusSeconds
        case .shortBreak: configuration.shortBreakSeconds
        case .longBreak: configuration.longBreakSeconds
        }
    }

    public func remainingSeconds(now: Date = .now) -> Int {
        switch state {
        case .paused:
            return max(0, pausedRemainingSeconds ?? phaseDurationSeconds)
        case .running:
            guard let phaseEndAt else { return phaseDurationSeconds }
            return max(0, Int(phaseEndAt.timeIntervalSince(now).rounded(.up)))
        case .idle:
            return phaseDurationSeconds
        }
    }

    public func progress(now: Date = .now) -> Double {
        let duration = max(1, phaseDurationSeconds)
        let remaining = remainingSeconds(now: now)
        return min(max(1 - Double(remaining) / Double(duration), 0), 1)
    }

    public var cycleIndex: Int {
        completedFocusSessions % max(1, configuration.longBreakEvery)
    }

    // MARK: Actions

    public mutating func startFocus(
        now: Date,
        taskTitle: String? = nil,
        subject: String? = nil,
        configuration: PomodoroConfiguration? = nil
    ) {
        if let configuration {
            self.configuration = configuration
        }
        phase = .focus
        state = .running
        sessionID = UUID()
        phaseStartedAt = now
        phaseEndAt = now.addingTimeInterval(TimeInterval(self.configuration.focusSeconds))
        pausedRemainingSeconds = nil
        self.taskTitle = taskTitle
        self.subject = subject
    }

    public mutating func pause(now: Date) {
        guard state == .running else { return }
        let remaining = remainingSeconds(now: now)
        state = .paused
        pausedRemainingSeconds = remaining
        phaseEndAt = nil
    }

    public mutating func resume(now: Date) {
        guard state == .paused else { return }
        let remaining = max(1, pausedRemainingSeconds ?? phaseDurationSeconds)
        state = .running
        pausedRemainingSeconds = nil
        phaseEndAt = now.addingTimeInterval(TimeInterval(remaining))
    }

    @discardableResult
    public mutating func tick(now: Date) -> PomodoroEvent? {
        guard state == .running, let endAt = phaseEndAt, now >= endAt else { return nil }

        switch phase {
        case .focus:
            let completed = CompletedFocus(
                sessionID: sessionID ?? UUID(),
                startedAt: phaseStartedAt ?? endAt,
                endedAt: endAt,
                focusedSeconds: configuration.focusSeconds,
                taskTitle: taskTitle,
                subject: subject
            )
            completedFocusSessions += 1

            let isLongBreak = completedFocusSessions % max(1, configuration.longBreakEvery) == 0
            let nextPhase: PomodoroPhase = isLongBreak ? .longBreak : .shortBreak
            phase = nextPhase
            state = .running
            sessionID = nil
            phaseStartedAt = endAt
            phaseEndAt = endAt.addingTimeInterval(TimeInterval(
                isLongBreak ? configuration.longBreakSeconds : configuration.shortBreakSeconds
            ))
            pausedRemainingSeconds = nil
            taskTitle = nil
            subject = nil
            return .focusCompleted(completed)

        case .shortBreak, .longBreak:
            let wasLongBreak = phase == .longBreak
            resetToIdleFocus(resetCycle: wasLongBreak)
            return .breakCompleted(wasLongBreak: wasLongBreak)
        }
    }

    @discardableResult
    public mutating func end(now: Date) -> PomodoroEvent? {
        switch phase {
        case .focus:
            guard state == .running || state == .paused, let sessionID else {
                resetToIdleFocus(resetCycle: false)
                return nil
            }
            let remaining = remainingSeconds(now: now)
            let elapsed = max(0, configuration.focusSeconds - remaining)
            if elapsed > 0 {
                let completed = CompletedFocus(
                    sessionID: sessionID,
                    startedAt: phaseStartedAt ?? now,
                    endedAt: now,
                    focusedSeconds: elapsed,
                    taskTitle: taskTitle,
                    subject: subject
                )
                resetToIdleFocus(resetCycle: false)
                return .focusEndedEarly(completed)
            }
            resetToIdleFocus(resetCycle: false)
            return nil
        case .shortBreak, .longBreak:
            resetToIdleFocus(resetCycle: false)
            return .breakEnded
        }
    }

    public mutating func reset() {
        resetToIdleFocus(resetCycle: true)
    }

    public mutating func updateConfiguration(_ configuration: PomodoroConfiguration) {
        self.configuration = configuration
    }

    private mutating func resetToIdleFocus(resetCycle: Bool) {
        phase = .focus
        state = .idle
        sessionID = nil
        phaseStartedAt = nil
        phaseEndAt = nil
        pausedRemainingSeconds = nil
        taskTitle = nil
        subject = nil
        if resetCycle {
            completedFocusSessions = 0
        }
    }
}
