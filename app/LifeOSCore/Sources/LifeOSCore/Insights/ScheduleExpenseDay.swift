import Foundation

/// Calendar markers describe saved spending, independent of task search or completion filters.
public struct ScheduleExpenseDay: Hashable, Sendable {
    public let transactionCount: Int
    public let totals: [MoneyMath.CurrencyTotal]

    public static func grouped(
        transactions: [MoneyTransaction],
        calendar: Calendar = .current
    ) -> [Date: ScheduleExpenseDay] {
        let expenses = transactions.filter { $0.kind == .expense && $0.amountMinor > 0 }
        let groups = Dictionary(grouping: expenses) { calendar.startOfDay(for: $0.occurredAt) }
        return groups.mapValues { records in
            ScheduleExpenseDay(
                transactionCount: records.count,
                totals: MoneyMath.totalsByCurrency(records.map(\.money))
            )
        }
    }
}
