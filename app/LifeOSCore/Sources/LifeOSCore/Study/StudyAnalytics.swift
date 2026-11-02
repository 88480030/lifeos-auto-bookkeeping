import Foundation

// MARK: - Study result types

public struct StudyTotals: Hashable, Sendable {
    public var focusedSeconds: Int
    public var pomodoroCount: Int

    public var minutes: Int { focusedSeconds / 60 }

    public init(focusedSeconds: Int = 0, pomodoroCount: Int = 0) {
        self.focusedSeconds = max(0, focusedSeconds)
        self.pomodoroCount = max(0, pomodoroCount)
    }
}

public struct DailyStudyTotal: Hashable, Sendable, Identifiable {
    public var day: Date
    public var focusedSeconds: Int

    public var id: Date { day }

    public init(day: Date, focusedSeconds: Int) {
        self.day = day
        self.focusedSeconds = focusedSeconds
    }
}

public struct SubjectStudyTotal: Hashable, Sendable, Identifiable {
    public var subject: String
    public var focusedSeconds: Int

    public var id: String { subject }

    public init(subject: String, focusedSeconds: Int) {
        self.subject = subject
        self.focusedSeconds = focusedSeconds
    }
}

// MARK: - Study analytics

/// 学习统计的纯函数集合。只统计 `.focus` 类型的真实学习记录。
public enum StudyAnalytics {
    public static func focusSessions(_ sessions: [StudySession], in interval: DateInterval) -> [StudySession] {
        sessions.filter {
            $0.kind == .focus
                && $0.focusedSeconds > 0
                && $0.startedAt >= interval.start
                && $0.startedAt < interval.end
        }
    }

    public static func totals(_ sessions: [StudySession], in interval: DateInterval) -> StudyTotals {
        let focus = focusSessions(sessions, in: interval)
        let seconds = focus.reduce(0) { $0 + $1.focusedSeconds }
        return StudyTotals(focusedSeconds: seconds, pomodoroCount: focus.count)
    }

    public static func totals(
        _ sessions: [StudySession],
        on day: Date,
        calendar: Calendar = .current
    ) -> StudyTotals {
        let interval = calendar.dateInterval(of: .day, for: day)
            ?? DateInterval(start: calendar.startOfDay(for: day), duration: 86_400)
        return totals(sessions, in: interval)
    }

    public static func dailyTotals(
        _ sessions: [StudySession],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [DailyStudyTotal] {
        var grouped: [Date: Int] = [:]
        for session in focusSessions(sessions, in: interval) {
            let day = calendar.startOfDay(for: session.startedAt)
            grouped[day, default: 0] += session.focusedSeconds
        }
        return grouped
            .map { DailyStudyTotal(day: $0.key, focusedSeconds: $0.value) }
            .sorted { $0.day < $1.day }
    }

    public static func subjectTotals(
        _ sessions: [StudySession],
        in interval: DateInterval
    ) -> [SubjectStudyTotal] {
        var grouped: [String: Int] = [:]
        for session in focusSessions(sessions, in: interval) {
            let subject = session.subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let key = subject.isEmpty ? "未分类" : subject
            grouped[key, default: 0] += session.focusedSeconds
        }
        return grouped
            .map { SubjectStudyTotal(subject: $0.key, focusedSeconds: $0.value) }
            .sorted { $0.focusedSeconds > $1.focusedSeconds }
    }

    /// 连续学习天数：从今天（或昨天）向前数，有多少天有真实专注记录。
    public static func streak(
        _ sessions: [StudySession],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        let days = Set(
            sessions
                .filter { $0.kind == .focus && $0.focusedSeconds > 0 }
                .map { calendar.startOfDay(for: $0.startedAt) }
        )
        guard !days.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    public static func goalProgress(focusedSeconds: Int, dailyGoalMinutes: Int) -> Double {
        guard dailyGoalMinutes > 0 else { return focusedSeconds > 0 ? 1 : 0 }
        return min(max(Double(focusedSeconds) / Double(dailyGoalMinutes * 60), 0), 1)
    }

    public static func weekInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 86_400)
    }

    public static func monthInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 30 * 86_400)
    }
}
