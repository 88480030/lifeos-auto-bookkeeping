import Foundation

/// One dated list for study and schedule records. Creation dates never schedule work.
public struct ReminderAgendaSnapshot {
    public enum Scope { case today, scheduled }
    public enum Entry: Identifiable {
        case schedule(ScheduleTask)
        case study(StudyTask)

        public var id: String {
            switch self {
            case .schedule(let task): "schedule:\(task.id)"
            case .study(let task): "study:\(task.id)"
            }
        }
        public var title: String {
            switch self { case .schedule(let task): task.title; case .study(let task): task.title }
        }
        public var isCompleted: Bool {
            switch self { case .schedule(let task): task.isCompleted; case .study(let task): task.isCompleted }
        }
        public var date: Date? {
            switch self { case .schedule(let task): task.startAt; case .study(let task): task.plannedDate }
        }
        fileprivate var createdAt: Date {
            switch self { case .schedule(let task): task.createdAt; case .study(let task): task.createdAt }
        }
        fileprivate func minute(calendar: Calendar) -> Int {
            switch self {
            case .schedule(let task):
                let parts = calendar.dateComponents([.hour, .minute], from: task.startAt)
                return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            case .study(let task): return task.plannedStartMinute ?? 1440
            }
        }
    }

    public struct Section: Identifiable {
        public let date: Date?
        public let entries: [Entry]
        public var id: String { date.map { "day:\($0.timeIntervalSince1970)" } ?? "undated" }
    }

    public let sections: [Section]
    public let scheduledPendingCount: Int
    public let todayPendingCount: Int
    public let undatedPendingCount: Int
    public let completedCount: Int

    public init(scheduleTasks: [ScheduleTask], studyTasks: [StudyTask], now: Date = .now,
                calendar: Calendar = .current, includesCompleted: Bool = false, scope: Scope = .scheduled) {
        let all = scheduleTasks.map(Entry.schedule) + studyTasks.map(Entry.study)
        let today = calendar.startOfDay(for: now)
        let todayEntries = all.filter { entry in
            entry.date.map { calendar.isDate($0, inSameDayAs: today) } ?? false
        }
        scheduledPendingCount = all.filter { !$0.isCompleted && $0.date != nil }.count
        todayPendingCount = todayEntries.filter { !$0.isCompleted }.count
        undatedPendingCount = all.filter { !$0.isCompleted && $0.date == nil }.count
        let scoped = scope == .today ? todayEntries : all
        completedCount = scoped.filter(\.isCompleted).count
        let visible = scoped.filter { includesCompleted || !$0.isCompleted }
        let dated = visible.filter { $0.date != nil }
        var grouped = Dictionary(grouping: dated) { calendar.startOfDay(for: $0.date!) }
        if grouped[today] == nil { grouped[today] = [] }
        func sorted(_ entries: [Entry]) -> [Entry] {
            entries.sorted {
                if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
                let left = $0.minute(calendar: calendar), right = $1.minute(calendar: calendar)
                if left != right { return left < right }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id < $1.id
            }
        }
        var result = grouped.keys.sorted().map { Section(date: $0, entries: sorted(grouped[$0] ?? [])) }
        let undated = sorted(visible.filter { $0.date == nil })
        if !undated.isEmpty { result.append(Section(date: nil, entries: undated)) }
        sections = result
    }
}
