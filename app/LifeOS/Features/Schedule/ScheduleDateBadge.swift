import SwiftUI

/// 已记支出的角色与日期共用一个区域，不再占用额外标记行。
struct ScheduleDateBadge: View {
    let dayNumber: Int
    let summary: ScheduleExpenseDay?

    @ScaledMetric(relativeTo: .subheadline) private var side: CGFloat = 40
    @ScaledMetric(relativeTo: .caption) private var numberSize: CGFloat = 13

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let summary {
                Image(summary.calendarAvatarTier.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .background(summary.calendarAvatarTier.wash, in: Circle())

                Text("\(dayNumber)")
                    .font(.system(size: numberSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ArchiveTheme.ink)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(ArchiveTheme.paperRaised, in: RoundedRectangle(cornerRadius: 5))
            } else {
                Text("\(dayNumber)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: side, height: side)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

extension ScheduleExpenseDay {
    /// 仅用人民币判断五档；仅外币支出用小熊作通用角色标记，不作汇率换算。
    var calendarAvatarTier: DailySpendingTier {
        let yuanExpense = totals.first { $0.currencyCode.uppercased() == "CNY" }?.minorUnits ?? 0
        return DailySpendingTier.matching(expenseMinor: yuanExpense, currencyCode: "CNY") ?? .thirty
    }
}
