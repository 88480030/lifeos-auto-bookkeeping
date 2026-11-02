import Foundation

/// A read-only, local snapshot. It never writes records or contacts a service.
public struct DailyBriefSnapshot {
    public let todayTransactions: [MoneyTransaction]
    public let expenseTotals: [MoneyMath.CurrencyTotal]
    public let incomeTotals: [MoneyMath.CurrencyTotal]
    public let studyTotals: StudyTotals
    public let todayTasks: [ScheduleTask]
    public let completedScheduleCount: Int
    public let overdueScheduleCount: Int
    public let currentSchedule: ScheduleTask?
    public let nextSchedule: ScheduleTask?
    public let todayStudyTasks: [StudyTask]
    public let nextStudyTask: StudyTask?
    public var todayPlanCount: Int { todayTasks.count + todayStudyTasks.count }
    public var completedPlanCount: Int { completedScheduleCount + todayStudyTasks.filter(\.isCompleted).count }
    public var pendingPlanCount: Int { pendingScheduleCount + todayStudyTasks.filter { !$0.isCompleted }.count }
    public let pendingStudyTasks: [StudyTask]

    public var pendingScheduleCount: Int { todayTasks.count - completedScheduleCount }

    public init(
        transactions: [MoneyTransaction],
        sessions: [StudySession],
        scheduleTasks: [ScheduleTask],
        studyTasks: [StudyTask],
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let interval = DayKey.dayInterval(containing: now, calendar: calendar)
        let records = transactions.filter { $0.occurredAt >= interval.start && $0.occurredAt < interval.end }
        todayTransactions = records
        expenseTotals = MoneyMath.totalsByCurrency(records.filter { $0.kind == .expense }.map(\.money))
        incomeTotals = MoneyMath.totalsByCurrency(records.filter { $0.kind == .income }.map(\.money))
        studyTotals = StudyAnalytics.totals(sessions, on: now, calendar: calendar)
        let today = scheduleTasks.filter { $0.startAt >= interval.start && $0.startAt < interval.end }
            .sorted { $0.startAt < $1.startAt }
        todayTasks = today
        completedScheduleCount = today.filter(\.isCompleted).count
        overdueScheduleCount = today.filter { !$0.isCompleted && $0.endAt <= now }.count
        currentSchedule = scheduleTasks.filter {
            !$0.isCompleted && $0.startAt <= now && $0.endAt > now
        }.min { $0.startAt < $1.startAt }
        nextSchedule = scheduleTasks.filter { !$0.isCompleted && $0.startAt > now }
            .min { $0.startAt < $1.startAt }
        todayStudyTasks = StudyPlanning.tasks(studyTasks, on: now, calendar: calendar)
        nextStudyTask = studyTasks.filter { !$0.isCompleted && ($0.plannedDate ?? .distantPast) >= interval.end }
            .min(by: Self.studyComesBefore)
        pendingStudyTasks = studyTasks.filter { !$0.isCompleted }.sorted(by: Self.studyComesBefore)
    }

    private static func studyComesBefore(_ left: StudyTask, _ right: StudyTask) -> Bool {
        let leftDate = left.plannedDate ?? .distantFuture
        let rightDate = right.plannedDate ?? .distantFuture
        if leftDate != rightDate { return leftDate < rightDate }
        if left.plannedStartMinute != right.plannedStartMinute {
            return (left.plannedStartMinute ?? 1440) < (right.plannedStartMinute ?? 1440)
        }
        return left.createdAt < right.createdAt
    }
}

/// Planned study days are distinct from creation dates and from undated backlog.
public enum StudyPlanning {
    public static func tasks(_ tasks: [StudyTask], on day: Date, calendar: Calendar = .current) -> [StudyTask] {
        let interval = DayKey.dayInterval(containing: day, calendar: calendar)
        return tasks.filter { task in
            guard let date = task.plannedDate else { return false }
            return date >= interval.start && date < interval.end
        }.sorted {
            if $0.plannedStartMinute != $1.plannedStartMinute { return ($0.plannedStartMinute ?? 1440) < ($1.plannedStartMinute ?? 1440) }
            return $0.createdAt < $1.createdAt
        }
    }
    public static func automaticFocusTask(_ tasks: [StudyTask], now: Date = .now, calendar: Calendar = .current) -> StudyTask? {
        self.tasks(tasks, on: now, calendar: calendar).first { !$0.isCompleted }
    }
}
