import Foundation

// MARK: - Result types

public struct FinanceTotals: Hashable, Sendable {
    public var currencyCode: String
    public var incomeMinor: Int
    public var expenseMinor: Int

    public var balanceMinor: Int { incomeMinor - expenseMinor }

    public init(currencyCode: String, incomeMinor: Int = 0, expenseMinor: Int = 0) {
        self.currencyCode = currencyCode.uppercased()
        self.incomeMinor = incomeMinor
        self.expenseMinor = expenseMinor
    }
}

public struct CategoryTotal: Hashable, Sendable, Identifiable {
    public var categoryRaw: String
    public var minorUnits: Int

    public var id: String { categoryRaw }

    public init(categoryRaw: String, minorUnits: Int) {
        self.categoryRaw = categoryRaw
        self.minorUnits = minorUnits
    }
}

public struct DailyTotal: Hashable, Sendable, Identifiable {
    public var day: Date
    public var minorUnits: Int

    public var id: Date { day }

    public init(day: Date, minorUnits: Int) {
        self.day = day
        self.minorUnits = minorUnits
    }
}

public struct BudgetStatus: Hashable, Sendable {
    public var amountMinor: Int
    public var spentMinor: Int

    public var remainingMinor: Int { amountMinor - spentMinor }
    public var isOverBudget: Bool { spentMinor > amountMinor }

    public var progress: Double {
        guard amountMinor > 0 else { return spentMinor > 0 ? 1 : 0 }
        return min(max(Double(spentMinor) / Double(amountMinor), 0), 1)
    }

    public init(amountMinor: Int, spentMinor: Int) {
        self.amountMinor = max(0, amountMinor)
        self.spentMinor = max(0, spentMinor)
    }
}

// MARK: - Analytics

/// 财务统计的纯函数集合。所有金额只会在单一币种内计算，绝不跨币种相加。
/// 时间范围包含起点、不包含终点，午夜记录只归属于新的一天或月份。
public enum FinanceAnalytics {
    public static func monthInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
    }

    public static func weekInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 86_400)
    }

    public static func totals(
        _ transactions: [MoneyTransaction],
        in interval: DateInterval,
        currencyCode: String
    ) -> FinanceTotals {
        let code = currencyCode.uppercased()
        var totals = FinanceTotals(currencyCode: code)
        for transaction in transactions where transaction.currencyCode.uppercased() == code {
            guard transaction.occurredAt >= interval.start,
                  transaction.occurredAt < interval.end else { continue }
            switch transaction.kind {
            case .expense: totals.expenseMinor += transaction.amountMinor
            case .income: totals.incomeMinor += transaction.amountMinor
            }
        }
        return totals
    }

    public static func totals(
        _ transactions: [MoneyTransaction],
        on day: Date,
        calendar: Calendar = .current,
        currencyCode: String
    ) -> FinanceTotals {
        let interval = calendar.dateInterval(of: .day, for: day)
            ?? DateInterval(start: calendar.startOfDay(for: day), duration: 86_400)
        return totals(transactions, in: interval, currencyCode: currencyCode)
    }

    public static func categoryTotals(
        _ transactions: [MoneyTransaction],
        kind: TransactionKind,
        in interval: DateInterval,
        currencyCode: String
    ) -> [CategoryTotal] {
        let code = currencyCode.uppercased()
        var grouped: [String: Int] = [:]
        for transaction in transactions {
            guard transaction.kind == kind,
                  transaction.currencyCode.uppercased() == code,
                  transaction.occurredAt >= interval.start,
                  transaction.occurredAt < interval.end else { continue }
            grouped[transaction.categoryRaw, default: 0] += transaction.amountMinor
        }
        return grouped
            .map { CategoryTotal(categoryRaw: $0.key, minorUnits: $0.value) }
            .sorted { $0.minorUnits > $1.minorUnits }
    }

    public static func dailyExpenses(
        _ transactions: [MoneyTransaction],
        in interval: DateInterval,
        currencyCode: String,
        calendar: Calendar = .current
    ) -> [DailyTotal] {
        let code = currencyCode.uppercased()
        var grouped: [Date: Int] = [:]
        for transaction in transactions {
            guard transaction.kind == .expense,
                  transaction.currencyCode.uppercased() == code,
                  transaction.occurredAt >= interval.start,
                  transaction.occurredAt < interval.end else { continue }
            let day = calendar.startOfDay(for: transaction.occurredAt)
            grouped[day, default: 0] += transaction.amountMinor
        }
        return grouped
            .map { DailyTotal(day: $0.key, minorUnits: $0.value) }
            .sorted { $0.day < $1.day }
    }

    public static func budgetStatus(amountMinor: Int, spentMinor: Int) -> BudgetStatus {
        BudgetStatus(amountMinor: amountMinor, spentMinor: spentMinor)
    }
}
