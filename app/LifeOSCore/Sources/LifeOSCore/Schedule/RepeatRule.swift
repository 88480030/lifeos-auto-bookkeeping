import Foundation

// MARK: - Repeat rule

public enum RepeatRule: String, Codable, CaseIterable, Sendable {
    case none
    case daily
    case weekdays
    case weekly
    case monthly

    public var displayName: String {
        switch self {
        case .none: "不重复"
        case .daily: "每天"
        case .weekdays: "工作日"
        case .weekly: "每周"
        case .monthly: "每月"
        }
    }

    public static func from(_ raw: String?) -> RepeatRule {
        guard let raw, let rule = RepeatRule(rawValue: raw) else { return .none }
        return rule
    }

    /// 生成重复任务的日期（包含起始日期）。
    public func occurrences(
        startingAt start: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard count > 0 else { return [] }
        guard self != .none else { return [start] }

        var cursor = start
        if self == .weekdays {
            while isWeekend(cursor, calendar: calendar) {
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        var dates: [Date] = []
        while dates.count < count {
            dates.append(cursor)
            guard let next = nextDate(after: cursor, calendar: calendar) else { break }
            cursor = next
        }
        return dates
    }

    private func nextDate(after date: Date, calendar: Calendar) -> Date? {
        switch self {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekdays:
            var cursor = date
            repeat {
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
                cursor = next
            } while isWeekend(cursor, calendar: calendar)
            return cursor
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        }
    }

    private func isWeekend(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }
}

// MARK: - Schedule analytics

public enum ScheduleAnalytics {
    public static func tasks(
        _ tasks: [ScheduleTask],
        on day: Date,
        calendar: Calendar = .current
    ) -> [ScheduleTask] {
        tasks
            .filter { calendar.isDate($0.startAt, inSameDayAs: day) }
            .sorted { $0.startAt < $1.startAt }
    }

    public static func tasks(
        _ tasks: [ScheduleTask],
        in interval: DateInterval
    ) -> [ScheduleTask] {
        tasks
            .filter { $0.startAt >= interval.start && $0.startAt < interval.end }
            .sorted { $0.startAt < $1.startAt }
    }

    public static func nextTask(
        _ tasks: [ScheduleTask],
        after date: Date = .now
    ) -> ScheduleTask? {
        tasks
            .filter { !$0.isCompleted && $0.startAt >= date }
            .min { $0.startAt < $1.startAt }
    }

    public static func completionRate(_ tasks: [ScheduleTask]) -> Double {
        guard !tasks.isEmpty else { return 0 }
        let completed = tasks.filter(\.isCompleted).count
        return Double(completed) / Double(tasks.count)
    }

    public static func dayInterval(
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
    }
}
