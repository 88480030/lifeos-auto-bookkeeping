import Foundation

/// 首页仪表盘的数据聚合。所有数字都由 SwiftData 中的真实记录计算得出。
struct HomeDashboard {
    let now: Date
    let transactions: [MoneyTransaction]
    let sessions: [StudySession]
    let tasks: [ScheduleTask]

    let todayTransactions: [MoneyTransaction]
    let todaySessions: [StudySession]
    let todayTasks: [ScheduleTask]
    let nextTask: ScheduleTask?

    private let dayInterval: DateInterval

    init(
        transactions: [MoneyTransaction],
        sessions: [StudySession],
        tasks: [ScheduleTask],
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let interval = DayKey.dayInterval(containing: now, calendar: calendar)
        self.now = now
        self.transactions = transactions
        self.sessions = sessions
        self.tasks = tasks
        self.dayInterval = interval
        self.todayTransactions = transactions.filter { $0.occurredAt >= interval.start && $0.occurredAt < interval.end }
        self.todaySessions = sessions.filter {
            $0.kind == .focus && $0.startedAt < interval.end && $0.endedAt > interval.start
        }
        self.todayTasks = tasks
            .filter { $0.startAt >= interval.start && $0.startAt < interval.end }
            .sorted { $0.startAt < $1.startAt }
        let brief = DailyBriefSnapshot(transactions: [], sessions: [], scheduleTasks: tasks, studyTasks: [], now: now, calendar: calendar)
        self.nextTask = brief.currentSchedule ?? brief.nextSchedule
    }

    var todayExpenseTotals: [MoneyMath.CurrencyTotal] {
        MoneyMath.totalsByCurrency(
            todayTransactions
                .filter { $0.kind == .expense }
                .map(\.money)
        )
    }

    var todayIncomeTotals: [MoneyMath.CurrencyTotal] {
        MoneyMath.totalsByCurrency(
            todayTransactions
                .filter { $0.kind == .income }
                .map(\.money)
        )
    }

    var todayStudySeconds: Int {
        // Use the same effective focus duration as the Study screen. Wall time
        // includes pauses and must not be counted as time spent studying.
        StudyAnalytics.totals(sessions, in: dayInterval).focusedSeconds
    }

    var todayStudyMinutes: Int {
        todayStudySeconds / 60
    }

    var todayTaskCount: Int {
        todayTasks.count
    }

    var completedTaskCount: Int {
        todayTasks.filter { $0.isCompleted }.count
    }

    var completionRatio: Double {
        guard todayTaskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(todayTaskCount)
    }

}
