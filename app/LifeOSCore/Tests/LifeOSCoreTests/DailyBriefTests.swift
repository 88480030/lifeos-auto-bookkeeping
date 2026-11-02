import Foundation
import Testing
@testable import LifeOSCore

private func briefCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}

private func briefDate(_ day: Int, _ hour: Int = 0) -> Date {
    briefCalendar().date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
}

@Test func dailyBriefKeepsCurrenciesSeparateAndExcludesTomorrowMidnight() {
    let snapshot = DailyBriefSnapshot(transactions: [
        MoneyTransaction(amountMinor: 1200, currencyCode: "CNY", kind: .expense, categoryRaw: "dining", occurredAt: briefDate(24, 9)),
        MoneyTransaction(amountMinor: 500, currencyCode: "JPY", kind: .expense, categoryRaw: "dining", occurredAt: briefDate(24, 10)),
        MoneyTransaction(amountMinor: 9000, currencyCode: "CNY", kind: .income, categoryRaw: "other", occurredAt: briefDate(24, 8)),
        MoneyTransaction(amountMinor: 999, currencyCode: "CNY", kind: .expense, categoryRaw: "other", occurredAt: briefDate(25))
    ], sessions: [], scheduleTasks: [], studyTasks: [], now: briefDate(24, 12), calendar: briefCalendar())
    #expect(snapshot.todayTransactions.count == 3)
    #expect(snapshot.expenseTotals.first { $0.currencyCode == "CNY" }?.minorUnits == 1200)
    #expect(snapshot.expenseTotals.first { $0.currencyCode == "JPY" }?.minorUnits == 500)
    #expect(snapshot.incomeTotals.first?.minorUnits == 9000)
}

@Test func dailyBriefSeparatesOngoingOverdueAndFutureSchedules() {
    let ongoing = ScheduleTask(title: "正在进行", startAt: briefDate(24, 11), durationMinutes: 120)
    let ended = ScheduleTask(title: "待补办", startAt: briefDate(24, 9))
    let completed = ScheduleTask(title: "完成", startAt: briefDate(24, 8), isCompleted: true)
    let tomorrow = ScheduleTask(title: "明天", startAt: briefDate(25, 9))
    let snapshot = DailyBriefSnapshot(transactions: [], sessions: [], scheduleTasks: [tomorrow, ended, completed, ongoing], studyTasks: [], now: briefDate(24, 12), calendar: briefCalendar())
    #expect(snapshot.todayTasks.count == 3)
    #expect(snapshot.pendingScheduleCount == 2)
    #expect(snapshot.completedScheduleCount == 1)
    #expect(snapshot.overdueScheduleCount == 1)
    #expect(snapshot.currentSchedule?.id == ongoing.id)
    #expect(snapshot.nextSchedule?.id == tomorrow.id)
}

@Test func dailyBriefSortsPendingStudyByPlanAndUsesEffectiveFocusTime() {
    let unplanned = StudyTask(title: "未安排")
    let future = StudyTask(title: "明天", plannedDate: briefDate(25))
    let today = StudyTask(title: "今天", plannedDate: briefDate(24))
    let done = StudyTask(title: "完成", isCompleted: true)
    let sessions = [
        StudySession(startedAt: briefDate(24, 9), endedAt: briefDate(24, 10), focusedSeconds: 1200),
        StudySession(startedAt: briefDate(24, 10), endedAt: briefDate(24, 11), focusedSeconds: 300, kind: .shortBreak)
    ]
    let snapshot = DailyBriefSnapshot(transactions: [], sessions: sessions, scheduleTasks: [], studyTasks: [unplanned, done, future, today], now: briefDate(24, 12), calendar: briefCalendar())
    #expect(snapshot.pendingStudyTasks.map(\.title) == ["今天", "明天", "未安排"])
    #expect(snapshot.studyTotals.minutes == 20)
    #expect(snapshot.studyTotals.pomodoroCount == 1)
}

@Test func emptyDailyBriefHasNoInventedRecords() {
    let snapshot = DailyBriefSnapshot(transactions: [], sessions: [], scheduleTasks: [], studyTasks: [])
    #expect(snapshot.expenseTotals.isEmpty)
    #expect(snapshot.pendingScheduleCount == 0)
    #expect(snapshot.currentSchedule == nil)
    #expect(snapshot.nextSchedule == nil)
    #expect(snapshot.studyTotals.minutes == 0)
}

@Test func datedStudyAppearsInDailyPlanButFutureAndUndatedDoNot() {
    let yesterday = StudyTask(title: "旧任务", plannedDate: briefDate(28))
    let today = StudyTask(title: "今天学习", plannedDate: briefDate(29))
    let tomorrow = StudyTask(title: "30号开始", plannedDate: briefDate(30))
    let undated = StudyTask(title: "未排期")
    let tasks = [tomorrow, undated, yesterday, today]
    let snapshot = DailyBriefSnapshot(transactions: [], sessions: [], scheduleTasks: [], studyTasks: tasks, now: briefDate(29, 8), calendar: briefCalendar())
    #expect(snapshot.todayStudyTasks.map(\.title) == ["今天学习"])
    #expect(snapshot.todayPlanCount == 1)
    #expect(snapshot.pendingPlanCount == 1)
    #expect(snapshot.nextStudyTask?.id == tomorrow.id)
    #expect(StudyPlanning.automaticFocusTask([tomorrow, undated, yesterday], now: briefDate(29, 8), calendar: briefCalendar()) == nil)
    #expect(StudyPlanning.automaticFocusTask(tasks, now: briefDate(29, 8), calendar: briefCalendar())?.id == today.id)
    #expect(StudyPlanning.tasks(tasks, on: briefDate(30), calendar: briefCalendar()).map(\.title) == ["30号开始"])
}

@Test func dailyBriefNextAndPendingStudyUseTimeBeforeCreationOrder() {
    let today = StudyTask(title: "今天", plannedDate: briefDate(29), plannedStartMinute: 18 * 60)
    let early = StudyTask(title: "早晨词汇", plannedDate: briefDate(30), plannedStartMinute: 7 * 60 + 15, createdAt: briefDate(28, 10))
    let sameTime = StudyTask(title: "同一时刻后建", plannedDate: briefDate(30), plannedStartMinute: 7 * 60 + 15, createdAt: briefDate(28, 11))
    let late = StudyTask(title: "较早创建的刷题", plannedDate: briefDate(30), plannedStartMinute: 8 * 60, createdAt: briefDate(27))
    let untimed = StudyTask(title: "当天待定时间", plannedDate: briefDate(30), createdAt: briefDate(26))
    let laterDay = StudyTask(title: "再下一天", plannedDate: briefDate(31), plannedStartMinute: 6 * 60)
    let undated = StudyTask(title: "未安排日期")
    let completed = StudyTask(title: "已完成不再推荐", plannedDate: briefDate(30), plannedStartMinute: 6 * 60, isCompleted: true)
    let snapshot = DailyBriefSnapshot(transactions: [], sessions: [], scheduleTasks: [],
        studyTasks: [untimed, late, sameTime, completed, undated, laterDay, early, today],
        now: briefDate(29, 12), calendar: briefCalendar())

    #expect(snapshot.nextStudyTask?.id == early.id)
    let expectedIDs = [today.id, early.id, sameTime.id, late.id, untimed.id, laterDay.id, undated.id]
    #expect(snapshot.pendingStudyTasks.map(\.id) == expectedIDs)
}

@Test func reminderAgendaCombinesTimedWorkAndKeepsUndatedSeparate() {
    let schedule = ScheduleTask(title: "上午日程", startAt: briefDate(30, 9))
    let study = StudyTask(title: "早读", plannedDate: briefDate(30), plannedStartMinute: 8 * 60)
    let untimed = StudyTask(title: "当天时间待定", plannedDate: briefDate(30))
    let undated = StudyTask(title: "未排期", createdAt: briefDate(29))
    let done = StudyTask(title: "已完成", plannedDate: briefDate(29), isCompleted: true)
    let agenda = ReminderAgendaSnapshot(scheduleTasks: [schedule], studyTasks: [untimed, undated, done, study],
                                       now: briefDate(29, 12), calendar: briefCalendar())
    #expect(agenda.sections.count == 3)
    #expect(agenda.sections[0].date == briefDate(29))
    #expect(agenda.sections[0].entries.isEmpty)
    #expect(agenda.sections[1].entries.map(\.title) == ["早读", "上午日程", "当天时间待定"])
    #expect(agenda.sections[2].date == nil)
    #expect(agenda.sections[2].entries.map(\.title) == ["未排期"])
    #expect(agenda.scheduledPendingCount == 3)
    #expect(agenda.undatedPendingCount == 1)
    #expect(agenda.completedCount == 1)
}

@Test func reminderAgendaRetainsOverdueAndCompletedWithoutInventingDates() {
    let old = ScheduleTask(title: "过期", startAt: briefDate(28, 12))
    let study = StudyTask(title: "昨天已完成", plannedDate: briefDate(28), plannedStartMinute: 8 * 60, isCompleted: true)
    let noDate = StudyTask(title: "完成但未排期", isCompleted: true)
    let agenda = ReminderAgendaSnapshot(scheduleTasks: [old], studyTasks: [study, noDate],
        now: briefDate(29, 12), calendar: briefCalendar(), includesCompleted: true)
    #expect(agenda.sections.map(\.date) == [briefDate(28), briefDate(29), nil])
    #expect(agenda.sections[0].entries.map(\.title) == ["过期", "昨天已完成"])
    #expect(agenda.sections[2].entries.first?.title == "完成但未排期")
    #expect(agenda.scheduledPendingCount == 1)
    #expect(agenda.completedCount == 2)
}

@Test func reminderSmartListsUseActualDatesAndLivePendingCounts() {
    let today = StudyTask(title: "今天早读", plannedDate: briefDate(29), plannedStartMinute: 7 * 60)
    let tomorrow = StudyTask(title: "明天学习", plannedDate: briefDate(30))
    let undated = StudyTask(title: "未排期", createdAt: briefDate(29))
    let done = ScheduleTask(title: "今天已完成", startAt: briefDate(29, 8), isCompleted: true)
    let old = ScheduleTask(title: "昨天未完成", startAt: briefDate(28, 9))
    let tasks = [today, tomorrow, undated]
    let first = ReminderAgendaSnapshot(scheduleTasks: [done, old], studyTasks: tasks,
        now: briefDate(29, 12), calendar: briefCalendar(), scope: .today)
    #expect(first.todayPendingCount == 1)
    #expect(first.scheduledPendingCount == 3)
    #expect(first.completedCount == 1)
    #expect(first.sections.count == 1)
    #expect(first.sections[0].entries.map(\.title) == ["今天早读"])

    today.isCompleted = true
    let updated = ReminderAgendaSnapshot(scheduleTasks: [done, old], studyTasks: tasks,
        now: briefDate(29, 12), calendar: briefCalendar(), includesCompleted: true, scope: .today)
    #expect(updated.todayPendingCount == 0)
    #expect(updated.scheduledPendingCount == 2)
    #expect(updated.sections[0].entries.map(\.title) == ["今天早读", "今天已完成"])

    let nextDay = ReminderAgendaSnapshot(scheduleTasks: [done, old], studyTasks: tasks,
        now: briefDate(30, 12), calendar: briefCalendar(), scope: .today)
    #expect(nextDay.todayPendingCount == 1)
    #expect(nextDay.sections[0].entries.map(\.title) == ["明天学习"])
}

@Test func timedPlansRemindFifteenMinutesBeforeAndExcludeUntimedCompletedOrPast() {
    let noon = StudyTask(title: "学习数学", plannedDate: briefDate(30), plannedStartMinute: 12 * 60)
    let life = ScheduleTask(title: "看医生", startAt: briefDate(30, 13))
    let undated = StudyTask(title: "未排期")
    let untimed = StudyTask(title: "当天未定时间", plannedDate: briefDate(30))
    let completed = StudyTask(title: "已完成", plannedDate: briefDate(30), plannedStartMinute: 14 * 60, isCompleted: true)
    let reminders = PlanReminder.upcoming(scheduleTasks: [life], studyTasks: [noon, undated, untimed, completed],
        now: briefDate(30, 8), calendar: briefCalendar())
    #expect(reminders.map(\.title) == ["学习数学", "看医生"])
    #expect(reminders[0].fireAt == briefDate(30, 12).addingTimeInterval(-900))
    #expect(reminders[1].fireAt == briefDate(30, 13).addingTimeInterval(-900))
    #expect(PlanReminder.upcoming(scheduleTasks: [], studyTasks: [noon], now: briefDate(30, 12), calendar: briefCalendar()).isEmpty)
}

@Test func reminderQueueKeepsNearestPlansAcrossBothDomains() {
    let tasks = (0..<70).map { ScheduleTask(title: "安排\($0)", startAt: briefDate(30, 12).addingTimeInterval(Double($0 * 60))) }
    let study = StudyTask(title: "更早的学习", plannedDate: briefDate(30), plannedStartMinute: 11 * 60)
    let queue = PlanReminder.upcoming(scheduleTasks: tasks, studyTasks: [study], now: briefDate(30, 8), calendar: briefCalendar())
    #expect(queue.count == 60)
    #expect(queue.first?.title == "更早的学习")
    #expect(queue.last?.title == "安排58")
}
