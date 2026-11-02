import Foundation
import Testing
@testable import LifeOSCore

private func studyCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}

private func studyDate(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 10, year: Int = 2026) -> Date {
    let calendar = studyCalendar()
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func focusSession(
    startHour: Int,
    minutes: Int,
    subject: String,
    task: String = "学习",
    day: Int = 23
) -> StudySession {
    let start = studyDate(day, startHour, 0)
    return StudySession(
        startedAt: start,
        endedAt: start.addingTimeInterval(TimeInterval(minutes * 60)),
        focusedSeconds: minutes * 60,
        kind: .focus,
        taskTitle: task,
        subject: subject
    )
}

@Test func studyTotalsOnlyCountFocusSessions() {
    let interval = FinanceAnalytics.monthInterval(containing: studyDate(23, 12, 0), calendar: studyCalendar())
    let sessions = [
        focusSession(startHour: 9, minutes: 25, subject: "阅读"),
        focusSession(startHour: 10, minutes: 25, subject: "阅读"),
        StudySession(
            startedAt: studyDate(23, 11, 0),
            endedAt: studyDate(23, 11, 5),
            focusedSeconds: 300,
            kind: .shortBreak
        )
    ]

    let totals = StudyAnalytics.totals(sessions, in: interval)
    #expect(totals.minutes == 50)
    #expect(totals.pomodoroCount == 2)
}

@Test func studyDailyAndSubjectTotals() {
    let interval = FinanceAnalytics.monthInterval(containing: studyDate(23, 12, 0), calendar: studyCalendar())
    let sessions = [
        focusSession(startHour: 9, minutes: 25, subject: "阅读", day: 22),
        focusSession(startHour: 10, minutes: 25, subject: "英语", day: 23),
        focusSession(startHour: 14, minutes: 50, subject: "英语", day: 23)
    ]

    let daily = StudyAnalytics.dailyTotals(sessions, in: interval, calendar: studyCalendar())
    #expect(daily.count == 2)
    #expect(daily[0].focusedSeconds == 25 * 60)
    #expect(daily[1].focusedSeconds == 75 * 60)

    let subjects = StudyAnalytics.subjectTotals(sessions, in: interval)
    #expect(subjects[0].subject == "英语")
    #expect(subjects[0].focusedSeconds == 75 * 60)
    #expect(subjects[1].subject == "阅读")
}

@Test func studyStreakCountsConsecutiveDays() {
    let sessions = [
        focusSession(startHour: 9, minutes: 25, subject: "阅读", day: 23),
        focusSession(startHour: 9, minutes: 25, subject: "阅读", day: 22),
        focusSession(startHour: 9, minutes: 25, subject: "阅读", day: 21),
        focusSession(startHour: 9, minutes: 25, subject: "阅读", day: 18)
    ]

    let streak = StudyAnalytics.streak(
        sessions,
        calendar: studyCalendar(),
        now: studyDate(23, 12, 0)
    )
    #expect(streak == 3)
}

@Test func studyStreakKeepsYesterdayStreakAlive() {
    let sessions = [
        focusSession(startHour: 9, minutes: 25, subject: "阅读", day: 22),
        focusSession(startHour: 9, minutes: 25, subject: "阅读", day: 21)
    ]

    let streak = StudyAnalytics.streak(
        sessions,
        calendar: studyCalendar(),
        now: studyDate(23, 8, 0)
    )
    #expect(streak == 2)

    let stale = StudyAnalytics.streak(
        sessions,
        calendar: studyCalendar(),
        now: studyDate(24, 8, 0)
    )
    #expect(stale == 0)
}

@Test func studyGoalProgressClamps() {
    #expect(StudyAnalytics.goalProgress(focusedSeconds: 30 * 60, dailyGoalMinutes: 60) == 0.5)
    #expect(StudyAnalytics.goalProgress(focusedSeconds: 90 * 60, dailyGoalMinutes: 60) == 1)
    #expect(StudyAnalytics.goalProgress(focusedSeconds: 0, dailyGoalMinutes: 60) == 0)
    #expect(StudyAnalytics.goalProgress(focusedSeconds: 60, dailyGoalMinutes: 0) == 1)
}

@Test func midnightFocusSessionBelongsOnlyToFollowingDay() {
    let calendar = studyCalendar()
    let today = studyDate(23, 0, 0)
    let tomorrow = studyDate(24, 0, 0)
    let todayInterval = calendar.dateInterval(of: .day, for: today)!
    let tomorrowInterval = calendar.dateInterval(of: .day, for: tomorrow)!
    let first = focusSession(startHour: 0, minutes: 25, subject: "当日", day: 23)
    let late = focusSession(startHour: 23, minutes: 50, subject: "当日", day: 23)
    let midnight = focusSession(startHour: 0, minutes: 10, subject: "次日", day: 24)
    let sessions = [
        focusSession(startHour: 23, minutes: 20, subject: "前日", day: 22),
        first,
        late,
        midnight,
        focusSession(startHour: 0, minutes: 30, subject: "后日", day: 25)
    ]

    let todays = StudyAnalytics.focusSessions(sessions, in: todayInterval)
    let tomorrows = StudyAnalytics.focusSessions(sessions, in: tomorrowInterval)
    #expect(todays.map(\.id) == [first.id, late.id])
    #expect(tomorrows.map(\.id) == [midnight.id])

    let todayTotals = StudyAnalytics.totals(sessions, on: today, calendar: calendar)
    let tomorrowTotals = StudyAnalytics.totals(sessions, on: tomorrow, calendar: calendar)
    #expect(todayTotals.focusedSeconds == 75 * 60)
    #expect(todayTotals.pomodoroCount == 2)
    #expect(tomorrowTotals.focusedSeconds == 10 * 60)
    #expect(tomorrowTotals.pomodoroCount == 1)

    let daily = StudyAnalytics.dailyTotals(sessions, in: todayInterval, calendar: calendar)
    #expect(daily.count == 1)
    #expect(daily.first?.day == today)
    #expect(daily.first?.focusedSeconds == 75 * 60)
    let subjects = StudyAnalytics.subjectTotals(sessions, in: todayInterval)
    #expect(subjects.count == 1)
    #expect(subjects.first?.subject == "当日")
    #expect(subjects.first?.focusedSeconds == 75 * 60)
}
