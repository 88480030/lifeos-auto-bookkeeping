import Foundation

/// Converts the app's real records to the minimal extension payload.
public enum LifeOSWidgetSnapshotBuilder {
    public static func make(transactions: [MoneyTransaction], scheduleTasks: [ScheduleTask],
                            machine: PomodoroMachine, now: Date = .now,
                            calendar: Calendar = .current) -> LifeOSWidgetSnapshot {
        let interval = calendar.dateInterval(of: .day, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 86_400)
        let expenses = transactions.filter {
            $0.kind == .expense && $0.currencyCode.uppercased() == "CNY" &&
            $0.occurredAt >= interval.start && $0.occurredAt < interval.end
        }
        let tasks = scheduleTasks.filter { $0.startAt >= interval.start && $0.startAt < interval.end }
        let pending = tasks.filter { !$0.isCompleted }.sorted {
            $0.startAt == $1.startAt ? $0.id.uuidString < $1.id.uuidString : $0.startAt < $1.startAt
        }
        let focus = LifeOSWidgetFocus(
            phase: machine.phase.rawValue,
            state: machine.state.rawValue,
            endAt: machine.isRunning ? machine.phaseEndAt : nil,
            // Running displays use the absolute deadline; avoid needless per-second rewrites.
            remainingSeconds: machine.isRunning ? 0 : machine.remainingSeconds(now: now),
            taskTitle: machine.taskTitle.map { String($0.prefix(80)) }
        )
        return LifeOSWidgetSnapshot(
            generatedAt: now, dayStart: interval.start, dayEnd: interval.end,
            todayExpenseMinor: expenses.reduce(0) { $0 + $1.amountMinor },
            todayExpenseCount: expenses.count,
            pendingCount: pending.count, completedCount: tasks.count - pending.count,
            pendingTasks: pending.prefix(3).map {
                LifeOSWidgetTask(title: String($0.title.prefix(80)), startAt: $0.startAt)
            },
            focus: focus
        )
    }
}
