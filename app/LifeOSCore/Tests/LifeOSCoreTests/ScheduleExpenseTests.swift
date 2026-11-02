import Foundation
import Testing
@testable import LifeOSCore

@Test func scheduleSpendingMarksOnlyPositiveSavedExpensesAndKeepsCurrenciesSeparate() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))!
    let records = [
        MoneyTransaction(amountMinor: 2000, currencyCode: "CNY", occurredAt: day),
        MoneyTransaction(amountMinor: 3000, currencyCode: "CNY", occurredAt: day),
        MoneyTransaction(amountMinor: 500, currencyCode: "JPY", occurredAt: day),
        MoneyTransaction(amountMinor: 10000, kind: .income, occurredAt: day),
        MoneyTransaction(amountMinor: 0, occurredAt: day)
    ]
    let summary = ScheduleExpenseDay.grouped(transactions: records, calendar: calendar)[day]
    #expect(summary?.transactionCount == 3)
    #expect(summary?.totals.first { $0.currencyCode == "CNY" }?.minorUnits == 5000)
    #expect(summary?.totals.first { $0.currencyCode == "JPY" }?.minorUnits == 500)
    #expect(summary?.totals.count == 2)
}

@Test func scheduleSpendingCalendarUsesLocalMidnightAndDoesNotMarkIncomeOnlyDays() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))!
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
    let later = calendar.date(byAdding: .day, value: 2, to: day)!
    let records = [
        MoneyTransaction(amountMinor: 800, occurredAt: tomorrow.addingTimeInterval(-1)),
        MoneyTransaction(amountMinor: 600, occurredAt: tomorrow),
        MoneyTransaction(amountMinor: 900, kind: .income, occurredAt: later)
    ]
    let days = ScheduleExpenseDay.grouped(transactions: records, calendar: calendar)
    #expect(days[day]?.totals.first?.minorUnits == 800)
    #expect(days[tomorrow]?.totals.first?.minorUnits == 600)
    #expect(days[later] == nil)
}
