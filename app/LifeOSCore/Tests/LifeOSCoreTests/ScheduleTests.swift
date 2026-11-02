import Foundation
import Testing
@testable import LifeOSCore

private func scheduleCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}

private func scheduleDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
    scheduleCalendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

@Test func dailyRepeatGeneratesConsecutiveDates() {
    let calendar = scheduleCalendar()
    let start = scheduleDate(2026, 10, 23)
    let dates = RepeatRule.daily.occurrences(startingAt: start, count: 5, calendar: calendar)

    #expect(dates.count == 5)
    #expect(dates[0] == start)
    #expect(dates[4] == calendar.date(byAdding: .day, value: 4, to: start))
}

@Test func weekdayRepeatSkipsWeekend() {
    let calendar = scheduleCalendar()
    // 2026-10-23 是星期五
    let start = scheduleDate(2026, 10, 23)
    let dates = RepeatRule.weekdays.occurrences(startingAt: start, count: 5, calendar: calendar)

    #expect(dates.count == 5)
    #expect(calendar.component(.weekday, from: dates[0]) == 6) // 周五
    #expect(calendar.component(.weekday, from: dates[1]) == 2) // 周一
    #expect(calendar.component(.weekday, from: dates[2]) == 3)
}

@Test func monthlyRepeatAdvancesMonth() {
    let calendar = scheduleCalendar()
    let start = scheduleDate(2026, 10, 15)
    let dates = RepeatRule.monthly.occurrences(startingAt: start, count: 3, calendar: calendar)

    #expect(dates.count == 3)
    #expect(calendar.component(.month, from: dates[1]) == 11)
    #expect(calendar.component(.day, from: dates[1]) == 15)
}

@Test func scheduleAnalyticsGroupsAndFindsNextTask() {
    let calendar = scheduleCalendar()
    let today = scheduleDate(2026, 10, 23, 9)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

    let tasks = [
        ScheduleTask(title: "A", startAt: today, isCompleted: true),
        ScheduleTask(title: "B", startAt: calendar.date(byAdding: .hour, value: 2, to: today)!),
        ScheduleTask(title: "C", startAt: tomorrow)
    ]

    let todays = ScheduleAnalytics.tasks(tasks, on: today, calendar: calendar)
    #expect(todays.count == 2)
    #expect(todays[0].title == "A")

    let next = ScheduleAnalytics.nextTask(tasks, after: today)
    #expect(next?.title == "B")

    #expect(ScheduleAnalytics.completionRate(todays) == 0.5)
}

@Test func midnightTaskBelongsOnlyToFollowingDayInterval() {
    let calendar = scheduleCalendar()
    let today = scheduleDate(2026, 10, 23, 0)
    let tomorrow = scheduleDate(2026, 10, 24, 0)
    let todayInterval = ScheduleAnalytics.dayInterval(containing: today, calendar: calendar)
    let tomorrowInterval = ScheduleAnalytics.dayInterval(containing: tomorrow, calendar: calendar)
    let first = ScheduleTask(title: "当日零点", startAt: today, isCompleted: true)
    let late = ScheduleTask(title: "当日末尾", startAt: tomorrow.addingTimeInterval(-1))
    let midnight = ScheduleTask(title: "次日零点", startAt: tomorrow, isCompleted: true)
    let tasks = [
        midnight,
        ScheduleTask(title: "前日末尾", startAt: today.addingTimeInterval(-1)),
        late,
        first,
        ScheduleTask(title: "后日零点", startAt: tomorrowInterval.end)
    ]

    let todays = ScheduleAnalytics.tasks(tasks, in: todayInterval)
    let tomorrows = ScheduleAnalytics.tasks(tasks, in: tomorrowInterval)
    #expect(todays.map(\.id) == [first.id, late.id])
    #expect(tomorrows.map(\.id) == [midnight.id])
    #expect(ScheduleAnalytics.completionRate(todays) == 0.5)
    #expect(ScheduleAnalytics.completionRate(tomorrows) == 1)

    // Both calendar-day and interval callers must show the same list at midnight.
    #expect(todays.map(\.id) == ScheduleAnalytics.tasks(tasks, on: today, calendar: calendar).map(\.id))
    #expect(tomorrows.map(\.id) == ScheduleAnalytics.tasks(tasks, on: tomorrow, calendar: calendar).map(\.id))
}

@Test func lifeCalendarMarkerStaysSeparateFromStudyAndSurvivesCompletion() {
    let calendar = scheduleCalendar()
    let day = scheduleDate(2026, 11, 1, 0)
    let studyOnlyDay = scheduleDate(2026, 11, 2, 0)
    let event = ScheduleTask(title: "朋友聚会", startAt: scheduleDate(2026, 11, 1, 19))
    let studyCounts = [day: 13, studyOnlyDay: 13]
    let first = ScheduleCalendarDayPlan.grouped(scheduleTasks: [event], studyCounts: studyCounts, calendar: calendar)
    #expect(first[day]?.lifeCount == 1)
    #expect(first[day]?.studyCount == 13)
    #expect(first[day]?.hasLifeEvents == true)
    #expect(first[studyOnlyDay]?.lifeCount == 0)
    #expect(first[studyOnlyDay]?.hasLifeEvents == false)
    event.isCompleted = true
    #expect(ScheduleCalendarDayPlan.grouped(scheduleTasks: [event], studyCounts: [:], calendar: calendar)[day]?.hasLifeEvents == true)
}

@Test func lifeCalendarMarkerUsesEventDayAcrossMidnightAndRemovesDeletedEvent() {
    let calendar = scheduleCalendar()
    let first = scheduleDate(2026, 10, 31, 0)
    let next = scheduleDate(2026, 11, 1, 0)
    let event = ScheduleTask(title: "零点接人", startAt: next)
    let grouped = ScheduleCalendarDayPlan.grouped(scheduleTasks: [event], studyCounts: [first: 9], calendar: calendar)
    #expect(grouped[first]?.hasLifeEvents == false)
    #expect(grouped[next]?.lifeCount == 1)
    #expect(grouped[next]?.studyCount == 0)
    #expect(ScheduleCalendarDayPlan.grouped(scheduleTasks: [], studyCounts: [first: 9], calendar: calendar)[next] == nil)
}
