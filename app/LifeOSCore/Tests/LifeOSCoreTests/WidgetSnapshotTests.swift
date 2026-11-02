import Foundation
import Testing
@testable import LifeOSCore

private func widgetCalendar(_ zone: String = "Asia/Shanghai") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

private func widgetDate(_ day: Int = 27, _ hour: Int = 12) -> Date {
    widgetCalendar().date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
}

@Test func widgetSnapshotUsesOnlyTodaysCNYExpensesAndSchedule() throws {
    let now = widgetDate()
    let expenses = [
        MoneyTransaction(amountMinor: 2850, currencyCode: "CNY", occurredAt: now, note: "私密备注", merchant: "私密商家"),
        MoneyTransaction(amountMinor: 9999, currencyCode: "JPY", occurredAt: now),
        MoneyTransaction(amountMinor: 5000, currencyCode: "CNY", kind: .income, occurredAt: now),
        MoneyTransaction(amountMinor: 500, currencyCode: "CNY", occurredAt: widgetDate(26)),
        MoneyTransaction(amountMinor: 300, currencyCode: "CNY", occurredAt: widgetDate(28, 0))
    ]
    let tasks = [
        ScheduleTask(title: "晚课", startAt: widgetDate(27, 18)),
        ScheduleTask(title: "早课", startAt: widgetDate(27, 9)),
        ScheduleTask(title: "午课", startAt: widgetDate(27, 12)),
        ScheduleTask(title: "工作", startAt: widgetDate(27, 15)),
        ScheduleTask(title: "已完成", startAt: widgetDate(27, 10), isCompleted: true),
        ScheduleTask(title: "明天", startAt: widgetDate(28, 9))
    ]
    let snapshot = LifeOSWidgetSnapshotBuilder.make(transactions: expenses, scheduleTasks: tasks,
        machine: PomodoroMachine(), now: now, calendar: widgetCalendar())
    #expect(snapshot.todayExpenseMinor == 2850)
    #expect(snapshot.todayExpenseCount == 1)
    #expect(snapshot.pendingCount == 4)
    #expect(snapshot.completedCount == 1)
    #expect(snapshot.pendingTasks.map(\.title) == ["早课", "午课", "工作"])
    let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    #expect(!json.contains("私密备注"))
    #expect(!json.contains("私密商家"))
}

@Test func widgetSnapshotTracksFocusDeadlineAndPauseWithoutSecondBySecondChanges() {
    let now = widgetDate()
    var machine = PomodoroMachine()
    machine.startFocus(now: now, taskTitle: "阅读")
    let first = LifeOSWidgetSnapshotBuilder.make(transactions: [], scheduleTasks: [], machine: machine,
        now: now.addingTimeInterval(10), calendar: widgetCalendar())
    let later = LifeOSWidgetSnapshotBuilder.make(transactions: [], scheduleTasks: [], machine: machine,
        now: now.addingTimeInterval(20), calendar: widgetCalendar())
    #expect(first.focus.state == "running")
    #expect(first.focus.endAt == now.addingTimeInterval(1500))
    #expect(first.focus.remainingSeconds == 0)
    #expect(first.hasSameContent(as: later))
    machine.pause(now: now.addingTimeInterval(20))
    let paused = LifeOSWidgetSnapshotBuilder.make(transactions: [], scheduleTasks: [], machine: machine,
        now: now.addingTimeInterval(40), calendar: widgetCalendar())
    #expect(paused.focus.state == "paused")
    #expect(paused.focus.endAt == nil)
    #expect(paused.focus.remainingSeconds == 1480)
    #expect(!paused.hasSameContent(as: first))
}

@Test func widgetSnapshotRejectsMidnightAndChangedTimeZone() {
    let now = widgetDate()
    let snapshot = LifeOSWidgetSnapshotBuilder.make(transactions: [], scheduleTasks: [],
        machine: PomodoroMachine(), now: now, calendar: widgetCalendar())
    #expect(snapshot.isCurrentDay(at: now, calendar: widgetCalendar()))
    #expect(!snapshot.isCurrentDay(at: widgetDate(28, 0), calendar: widgetCalendar()))
    #expect(!snapshot.isCurrentDay(at: now, calendar: widgetCalendar("America/New_York")))
}

@Test func widgetSnapshotStoreDistinguishesMissingUnchangedAndUpdatedData() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(LifeOSWidgetStore.read(from: directory) == nil)
    let now = widgetDate()
    let first = LifeOSWidgetSnapshotBuilder.make(transactions: [], scheduleTasks: [],
        machine: PomodoroMachine(), now: now, calendar: widgetCalendar())
    #expect(LifeOSWidgetStore.writeIfChanged(first, to: directory))
    #expect(LifeOSWidgetStore.read(from: directory) == first)
    let later = LifeOSWidgetSnapshotBuilder.make(transactions: [], scheduleTasks: [],
        machine: PomodoroMachine(), now: now.addingTimeInterval(5), calendar: widgetCalendar())
    #expect(!LifeOSWidgetStore.writeIfChanged(later, to: directory))
    let changed = LifeOSWidgetSnapshotBuilder.make(transactions: [MoneyTransaction(amountMinor: 100, occurredAt: now)],
        scheduleTasks: [], machine: PomodoroMachine(), now: now, calendar: widgetCalendar())
    #expect(LifeOSWidgetStore.writeIfChanged(changed, to: directory))
    #expect(LifeOSWidgetStore.read(from: directory)?.todayExpenseMinor == 100)
}
