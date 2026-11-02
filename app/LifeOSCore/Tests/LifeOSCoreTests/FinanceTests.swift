import Foundation
import Testing
@testable import LifeOSCore

@Test func moneyParserHandlesCurrencyPrecision() {
    #expect(MoneyParser.minorUnits(from: "12.34", currencyCode: "CNY") == 1234)
    #expect(MoneyParser.minorUnits(from: "1500", currencyCode: "JPY") == 1500)
    #expect(MoneyParser.minorUnits(from: "0.1", currencyCode: "CNY") == 10)
    #expect(MoneyParser.minorUnits(from: "12.345", currencyCode: "CNY") == nil)
    #expect(MoneyParser.minorUnits(from: "12.5", currencyCode: "JPY") == nil)
    #expect(MoneyParser.minorUnits(from: "", currencyCode: "CNY") == nil)
    #expect(MoneyParser.minorUnits(from: "abc", currencyCode: "CNY") == nil)
    #expect(MoneyParser.minorUnits(from: "1 234.56", currencyCode: "CNY") == 123456)
}

@Test func analyticsNeverMixCurrencies() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let interval = FinanceAnalytics.monthInterval(containing: now)
    let cny = MoneyTransaction(amountMinor: 1000, currencyCode: "CNY", kind: .expense, occurredAt: now)
    let jpy = MoneyTransaction(amountMinor: 1500, currencyCode: "JPY", kind: .expense, occurredAt: now)

    let cnyTotals = FinanceAnalytics.totals([cny, jpy], in: interval, currencyCode: "CNY")
    let jpyTotals = FinanceAnalytics.totals([cny, jpy], in: interval, currencyCode: "JPY")

    #expect(cnyTotals.expenseMinor == 1000)
    #expect(cnyTotals.incomeMinor == 0)
    #expect(jpyTotals.expenseMinor == 1500)
}

@Test func dailyExpensesGroupByLocalDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let day1 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 9))!
    let day1Late = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 22))!
    let day2 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 8))!
    let interval = FinanceAnalytics.monthInterval(containing: day1, calendar: calendar)

    let transactions = [
        MoneyTransaction(amountMinor: 1000, currencyCode: "CNY", kind: .expense, occurredAt: day1),
        MoneyTransaction(amountMinor: 500, currencyCode: "CNY", kind: .expense, occurredAt: day1Late),
        MoneyTransaction(amountMinor: 800, currencyCode: "CNY", kind: .expense, occurredAt: day2),
        MoneyTransaction(amountMinor: 9999, currencyCode: "CNY", kind: .income, occurredAt: day2)
    ]

    let daily = FinanceAnalytics.dailyExpenses(
        transactions,
        in: interval,
        currencyCode: "CNY",
        calendar: calendar
    )

    #expect(daily.count == 2)
    #expect(daily[0].minorUnits == 1500)
    #expect(daily[1].minorUnits == 800)
}

@Test func categoryTotalsSortByAmountAndRespectKind() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let interval = FinanceAnalytics.monthInterval(containing: now)
    let transactions = [
        MoneyTransaction(amountMinor: 3000, currencyCode: "CNY", kind: .expense, categoryRaw: "餐饮", occurredAt: now),
        MoneyTransaction(amountMinor: 1000, currencyCode: "CNY", kind: .expense, categoryRaw: "交通", occurredAt: now),
        MoneyTransaction(amountMinor: 12000, currencyCode: "CNY", kind: .income, categoryRaw: "工资", occurredAt: now)
    ]

    let totals = FinanceAnalytics.categoryTotals(
        transactions,
        kind: .expense,
        in: interval,
        currencyCode: "CNY"
    )

    #expect(totals.count == 2)
    #expect(totals[0].categoryRaw == "餐饮")
    #expect(totals[0].minorUnits == 3000)
    #expect(totals[1].categoryRaw == "交通")
}

@Test func budgetStatusComputesRemainingAndOverflow() {
    let normal = FinanceAnalytics.budgetStatus(amountMinor: 300_000, spentMinor: 120_000)
    #expect(normal.remainingMinor == 180_000)
    #expect(normal.isOverBudget == false)
    #expect(normal.progress == 0.4)

    let over = FinanceAnalytics.budgetStatus(amountMinor: 100_000, spentMinor: 150_000)
    #expect(over.remainingMinor == -50_000)
    #expect(over.isOverBudget == true)
    #expect(over.progress == 1)
}

@Test func monthBoundaryRecordsBelongOnlyToFollowingMonth() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
    let interval = FinanceAnalytics.monthInterval(containing: start, calendar: calendar)
    let transactions = [
        MoneyTransaction(amountMinor: 800, kind: .expense, categoryRaw: "餐饮", occurredAt: start.addingTimeInterval(-1)),
        MoneyTransaction(amountMinor: 100, kind: .expense, categoryRaw: "餐饮", occurredAt: start),
        MoneyTransaction(amountMinor: 200, kind: .expense, categoryRaw: "餐饮", occurredAt: interval.end.addingTimeInterval(-1)),
        MoneyTransaction(amountMinor: 400, kind: .expense, categoryRaw: "餐饮", occurredAt: interval.end)
    ]

    let current = FinanceAnalytics.totals(transactions, in: interval, currencyCode: "CNY")
    let following = FinanceAnalytics.totals(
        transactions,
        in: FinanceAnalytics.monthInterval(containing: interval.end, calendar: calendar),
        currencyCode: "CNY"
    )
    #expect(current.expenseMinor == 300)
    #expect(following.expenseMinor == 400)

    let categories = FinanceAnalytics.categoryTotals(
        transactions, kind: .expense, in: interval, currencyCode: "CNY"
    )
    #expect(categories.count == 1)
    #expect(categories.first?.minorUnits == 300)

    let daily = FinanceAnalytics.dailyExpenses(
        transactions, in: interval, currencyCode: "CNY", calendar: calendar
    )
    #expect(daily.count == 2)
    #expect(daily.reduce(0) { $0 + $1.minorUnits } == 300)
    #expect(daily.allSatisfy { $0.day >= interval.start && $0.day < interval.end })
}

@Test func midnightRecordsBelongOnlyToFollowingDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24))!
    let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
    let transactions = [
        MoneyTransaction(amountMinor: 100, kind: .expense, occurredAt: day),
        MoneyTransaction(amountMinor: 200, kind: .expense, occurredAt: nextDay.addingTimeInterval(-1)),
        MoneyTransaction(amountMinor: 400, kind: .expense, occurredAt: nextDay)
    ]

    let current = FinanceAnalytics.totals(transactions, on: day, calendar: calendar, currencyCode: "CNY")
    let following = FinanceAnalytics.totals(transactions, on: nextDay, calendar: calendar, currencyCode: "CNY")
    #expect(current.expenseMinor == 300)
    #expect(following.expenseMinor == 400)
}

@Test func dayTotalsFollowCalendarAcrossDaylightSavingChange() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
    let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
    let transactions = [
        MoneyTransaction(amountMinor: 100, kind: .expense, occurredAt: day),
        MoneyTransaction(amountMinor: 200, kind: .expense, occurredAt: nextDay.addingTimeInterval(-1)),
        MoneyTransaction(amountMinor: 400, kind: .expense, occurredAt: nextDay)
    ]

    #expect(nextDay.timeIntervalSince(day) == 25 * 60 * 60)
    let totals = FinanceAnalytics.totals(transactions, on: day, calendar: calendar, currencyCode: "CNY")
    #expect(totals.expenseMinor == 300)
}
