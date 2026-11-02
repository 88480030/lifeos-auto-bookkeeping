import Foundation
import Testing
@testable import LifeOSCore

private func shanghaiCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}

@Test func dayAndMonthKeysUseProvidedTimeZone() throws {
    let calendar = shanghaiCalendar()
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 1, minute: 30)))

    #expect(DayKey.dayKey(for: date, calendar: calendar) == "2026-10-23")
    #expect(DayKey.monthKey(for: date, calendar: calendar) == "2026-10")
}

@Test func dayKeyChangesAtMidnightInLocalTimeZone() throws {
    let calendar = shanghaiCalendar()
    let beforeMidnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 23, minute: 59)))
    let afterMidnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 0, minute: 0)))

    #expect(DayKey.dayKey(for: beforeMidnight, calendar: calendar) == "2026-10-23")
    #expect(DayKey.dayKey(for: afterMidnight, calendar: calendar) == "2026-10-24")
}

@Test func dayIntervalCoversWholeLocalDay() throws {
    let calendar = shanghaiCalendar()
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 15)))
    let interval = DayKey.dayInterval(containing: date, calendar: calendar)

    #expect(DayKey.dayKey(for: interval.start, calendar: calendar) == "2026-10-23")
    #expect(DayKey.dayKey(for: interval.end.addingTimeInterval(-1), calendar: calendar) == "2026-10-23")
    #expect(interval.duration == 86_400)
}
