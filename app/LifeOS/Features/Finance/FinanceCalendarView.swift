import SwiftUI

struct FinanceCalendarView: View {
    let transactions: [MoneyTransaction]
    let month: Date
    let currencyCode: String
    @ObservedObject var categories: CustomCategoryStore
    let onEdit: (MoneyTransaction) -> Void
    let onDelete: (MoneyTransaction) -> Void
    var initialSelectedDate: Date? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var dayCellWidth: CGFloat = 44
    @State private var selectedDay: Date?

    private let calendar = Calendar.current
    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    private var monthInterval: DateInterval {
        FinanceAnalytics.monthInterval(containing: month)
    }

    private var dailyExpenses: [Date: Int] {
        let totals = FinanceAnalytics.dailyExpenses(
            transactions,
            in: monthInterval,
            currencyCode: currencyCode,
            calendar: calendar
        )
        return Dictionary(uniqueKeysWithValues: totals.map { ($0.day, $0.minorUnits) })
    }

    private var monthDays: [Date?] {
        let firstDay = monthInterval.start
        let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let weekday = calendar.component(.weekday, from: firstDay)
        let mondayOffset = (weekday + 5) % 7 // 周一 = 0
        var days: [Date?] = Array(repeating: nil, count: mondayOffset)
        for offset in 0..<dayCount {
            days.append(calendar.date(byAdding: .day, value: offset, to: firstDay))
        }
        return days
    }

    private var activeDay: Date {
        if let selectedDay, selectedDay >= monthInterval.start, selectedDay < monthInterval.end {
            return selectedDay
        }
        if let initialSelectedDate, initialSelectedDate >= monthInterval.start, initialSelectedDate < monthInterval.end {
            return calendar.startOfDay(for: initialSelectedDate)
        }
        let today = calendar.startOfDay(for: .now)
        return today >= monthInterval.start && today < monthInterval.end
            ? today : calendar.startOfDay(for: monthInterval.start)
    }

    private var dayTransactions: [MoneyTransaction] {
        transactions
            .filter { calendar.isDate($0.occurredAt, inSameDayAs: activeDay) }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    private var dayTotals: FinanceTotals {
        FinanceAnalytics.totals(
            dayTransactions,
            on: activeDay,
            calendar: calendar,
            currencyCode: currencyCode
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            calendarCard
            DailySpendingPanel(transactions: transactions, date: activeDay, currencyCode: currencyCode)
            dayDetail
        }
        .onAppear {
            if selectedDay == nil {
                selectedDay = activeDay
            }
        }
    }

    private var calendarCard: some View {
        SurfaceCard(padding: 16) {
            VStack(spacing: 12) {
                HStack {
                    Text("消费日历")
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text(currencyCode.uppercased() == "CNY" ? "五档消费头像" : "\(currencyCode) 支出")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Hairline()

                ScrollView(.horizontal) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: dayCellWidth), spacing: 4), count: 7), spacing: 6) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(minWidth: dayCellWidth)
                                .padding(.vertical, 4)
                        }

                        ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                            if let day {
                                dayCell(day)
                            } else {
                                Color.clear.frame(minHeight: 44)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .frame(minWidth: dayCellWidth * 7 + 24)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)

                Text(currencyCode.uppercased() == "CNY" ? "头像对应 ¥20 / 30 / 40 / 50 / 100 档；点日期查看实际账单。" : "非人民币按原币种显示，不套用人民币头像档位。")
                    .font(.caption)
                    .foregroundStyle(ArchiveTheme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let start = calendar.startOfDay(for: day)
        let expense = dailyExpenses[start] ?? 0
        let tier = DailySpendingTier.matching(expenseMinor: expense, currencyCode: currencyCode)
        let isSelected = calendar.isDate(day, inSameDayAs: activeDay)
        let isToday = calendar.isDateInToday(day)

        return Button {
            Haptics.select()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                selectedDay = start
            }
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.textPrimary)

                if let tier {
                    DailySpendingAvatar(tier: tier, size: 28)
                        .overlay(alignment: .bottomTrailing) {
                            if DailySpendingTier.isAboveHighestTier(expenseMinor: expense, currencyCode: currencyCode) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(ArchiveTheme.ink)
                                    .background(ArchiveTheme.paperRaised, in: Circle())
                            }
                        }
                } else if expense > 0 {
                    Image(systemName: "creditcard.fill")
                        .font(.caption)
                        .foregroundStyle(ArchiveTheme.inkSoft)
                        .frame(height: 28)
                } else {
                    Color.clear.frame(height: 28)
                }

                Circle()
                    .fill(isToday ? AppTheme.gold : .clear)
                    .frame(width: 3, height: 3)
            }
            .frame(minWidth: dayCellWidth, maxWidth: .infinity)
            .frame(minHeight: 68)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        expense > 0 ? (tier?.wash ?? ArchiveTheme.paperTint) : AppTheme.surface.opacity(0.35)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.gold : Color.clear, lineWidth: 1.4)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(AppFormatters.dateHeader(day))\(isToday ? "，今天" : "")")
        .accessibilityValue(expense > 0 ? "支出 " + MoneyFormatter.string(minorUnits: expense, currencyCode: currencyCode) + (tier.map { "，\($0.characterName)头像" } ?? "") + (DailySpendingTier.isAboveHighestTier(expenseMinor: expense, currencyCode: currencyCode) ? "，超出100元" : "") : "无支出")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: AppFormatters.dateHeader(activeDay),
                eyebrow: "Selected Day",
                trailing: "\(dayTransactions.count) 笔"
            )

            SurfaceCard(padding: 16) {
                VStack(spacing: 12) {
                    detailStatsLayout {
                        detailStat("支出", value: dayTotals.expenseMinor, color: AppTheme.coral)
                        detailStat("收入", value: dayTotals.incomeMinor, color: AppTheme.accent)
                        detailStat("结余", value: dayTotals.balanceMinor, color: dayTotals.balanceMinor >= 0 ? AppTheme.textPrimary : AppTheme.coral)
                    }

                    if dayTransactions.isEmpty {
                        EmptyStateView(
                            icon: "calendar",
                            title: "这一天还没有记录",
                            message: "选择其他日期，或回到明细页添加一笔。"
                        )
                    } else {
                        Hairline()
                        VStack(spacing: 0) {
                            ForEach(Array(dayTransactions.enumerated()), id: \.element.id) { index, transaction in
                                FinanceTransactionRow(
                                    transaction: transaction,
                                    categories: categories,
                                    onEdit: { onEdit(transaction) },
                                    onDelete: { onDelete(transaction) }
                                )
                                if index < dayTransactions.count - 1 {
                                    Rectangle()
                                        .fill(AppTheme.separator.opacity(0.55))
                                        .frame(height: 0.7)
                                        .padding(.leading, 66)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var detailStatsLayout: AnyLayout {
        dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
    }

    private func detailStat(_ title: String, value: Int, color: Color) -> some View {
        VStack(alignment: dynamicTypeSize >= .xxxLarge ? .leading : .center, spacing: 5) {
            Eyebrow(text: title, tint: AppTheme.textTertiary)
            Text(MoneyFormatter.string(minorUnits: value, currencyCode: currencyCode))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: dynamicTypeSize >= .xxxLarge ? .leading : .center)
    }
}
