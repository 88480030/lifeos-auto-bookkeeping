import SwiftUI

/// A calendar-day total from saved records, never an estimate or a planned task cost.
struct ScheduleExpenseSummaryView: View {
    let date: Date
    let summary: ScheduleExpenseDay?
    let onOpenRecords: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let summary {
            Button(action: onOpenRecords) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
                layout {
                    DailySpendingAvatar(tier: summary.calendarAvatarTier, size: 44, animates: true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("已记支出 · \(summary.transactionCount) 笔")
                            .font(.subheadline.weight(.semibold))
                        ForEach(summary.totals) { total in
                            Text(MoneyFormatter.string(minorUnits: total.minorUnits, currencyCode: total.currencyCode))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("查看当天账目")
                            .font(.caption)
                            .foregroundStyle(ArchiveTheme.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(ArchiveTheme.ink)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(ArchiveTheme.paperRaised, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ArchiveTheme.rule, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressableScaleStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(AppFormatters.dateHeader(date))，已记支出 \(summary.transactionCount) 笔，\(amounts(summary))")
            .accessibilityHint("查看当天账目")
            .accessibilityIdentifier("schedule.savedExpenses")
        }
    }

    private func amounts(_ summary: ScheduleExpenseDay) -> String {
        summary.totals.map { total in
            MoneyFormatter.string(minorUnits: total.minorUnits, currencyCode: total.currencyCode)
        }.joined(separator: "，")
    }
}

struct ScheduleExpenseLegend: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(DailySpendingTier.twenty.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text("日期头像表示当天有已记支出。人民币按五档显示；仅外币支出用小熊，不套人民币档位。")
                .font(.caption)
                .foregroundStyle(ArchiveTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
