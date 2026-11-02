import Foundation

/// The extension receives a small, read-only projection rather than the app database.
public struct LifeOSWidgetTask: Codable, Equatable, Sendable {
    public let title: String
    public let startAt: Date

    public init(title: String, startAt: Date) {
        self.title = title
        self.startAt = startAt
    }
}

public struct LifeOSWidgetFocus: Codable, Equatable, Sendable {
    /// Values use the app's PomodoroPhase and PomodoroRunState raw values.
    public let phase: String
    public let state: String
    public let endAt: Date?
    public let remainingSeconds: Int
    public let taskTitle: String?

    public init(phase: String, state: String, endAt: Date?, remainingSeconds: Int, taskTitle: String?) {
        self.phase = phase
        self.state = state
        self.endAt = endAt
        self.remainingSeconds = max(0, remainingSeconds)
        self.taskTitle = taskTitle
    }
}

public struct LifeOSWidgetSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let dayStart: Date
    public let dayEnd: Date
    public let todayExpenseMinor: Int
    public let todayExpenseCount: Int
    public let pendingCount: Int
    public let completedCount: Int
    public let pendingTasks: [LifeOSWidgetTask]
    public let focus: LifeOSWidgetFocus

    public init(generatedAt: Date, dayStart: Date, dayEnd: Date, todayExpenseMinor: Int,
                todayExpenseCount: Int, pendingCount: Int, completedCount: Int,
                pendingTasks: [LifeOSWidgetTask], focus: LifeOSWidgetFocus) {
        self.generatedAt = generatedAt
        self.dayStart = dayStart
        self.dayEnd = dayEnd
        self.todayExpenseMinor = todayExpenseMinor
        self.todayExpenseCount = todayExpenseCount
        self.pendingCount = pendingCount
        self.completedCount = completedCount
        self.pendingTasks = pendingTasks
        self.focus = focus
    }

    /// Reject both yesterday's snapshot and a snapshot from a different local time zone.
    public func isCurrentDay(at date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let interval = calendar.dateInterval(of: .day, for: date) else { return false }
        return dayStart == interval.start && dayEnd == interval.end && date >= dayStart && date < dayEnd
    }

    /// A timestamp alone must not cause WidgetKit reloads on unrelated database saves.
    public func hasSameContent(as other: Self) -> Bool {
        dayStart == other.dayStart && dayEnd == other.dayEnd &&
        todayExpenseMinor == other.todayExpenseMinor && todayExpenseCount == other.todayExpenseCount &&
        pendingCount == other.pendingCount && completedCount == other.completedCount &&
        pendingTasks == other.pendingTasks && focus == other.focus
    }
}

public enum LifeOSWidgetStore {
    public static var appGroupID: String {
        (Bundle.main.object(forInfoDictionaryKey: "LifeOSWidgetAppGroup") as? String)
            ?? "group.com.example.LifeOS"
    }
    private static let filename = "LifeOSWidgetSnapshot-v1.json"

    private static func groupDirectory() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// nil means unavailable, corrupt, or not yet synchronized, never an empty ledger.
    public static func read() -> LifeOSWidgetSnapshot? {
        guard let directory = groupDirectory() else { return nil }
        return read(from: directory)
    }

    public static func read(from directory: URL) -> LifeOSWidgetSnapshot? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(filename)) else { return nil }
        return try? JSONDecoder().decode(LifeOSWidgetSnapshot.self, from: data)
    }

    /// Atomic replacement keeps the extension from observing partially written JSON.
    /// Returning false means unavailable, unchanged, or failed; callers should not reload.
    @discardableResult
    public static func writeIfChanged(_ snapshot: LifeOSWidgetSnapshot) -> Bool {
        guard let directory = groupDirectory() else { return false }
        return writeIfChanged(snapshot, to: directory)
    }

    @discardableResult
    public static func writeIfChanged(_ snapshot: LifeOSWidgetSnapshot, to directory: URL) -> Bool {
        if let previous = read(from: directory), snapshot.hasSameContent(as: previous) { return false }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
