import SwiftUI

// MARK: - Segment control

enum FinanceSection: String, CaseIterable, Identifiable {
    case records
    case calendar
    case stats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .records: "明细"
        case .calendar: "日历"
        case .stats: "统计"
        }
    }
}

struct FinanceSegmentedControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: FinanceSection
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(FinanceSection.allCases) { section in
                Button {
                    guard selection != section else { return }
                    Haptics.select()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        selection = section
                    }
                } label: {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == section ? ArchiveTheme.ink : ArchiveTheme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background {
                            if selection == section {
                                Capsule(style: .continuous)
                                    .fill(ArchiveTheme.mintWash)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(ArchiveTheme.ink.opacity(0.8), lineWidth: 1.1)
                                    )
                                    .matchedGeometryEffect(id: "financeSection", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(ArchiveTheme.paperRaised)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(ArchiveTheme.ink.opacity(0.7), lineWidth: 1.4)
        )
    }
}

// MARK: - Transaction row

struct FinanceTransactionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let transaction: MoneyTransaction
    let categories: CustomCategoryStore
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var option: CategoryOption {
        CategoryCatalog.option(
            for: transaction.categoryRaw,
            kind: transaction.kind,
            custom: categories.categories
        )
    }

    private var title: String {
        if !transaction.note.isEmpty { return transaction.note }
        if !transaction.merchant.isEmpty { return transaction.merchant }
        return option.name
    }

    private var metadata: String {
        var parts = [option.name]
        if !transaction.merchant.isEmpty, transaction.merchant != title {
            parts.append(transaction.merchant)
        }
        parts.append(transaction.channel.displayName)
        parts.append(AppFormatters.time(transaction.occurredAt))
        return parts.joined(separator: " · ")
    }

    private var amount: some View {
        Text(FinanceFormatting.signedAmount(transaction))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(FinanceFormatting.amountColor(for: transaction.kind))
            .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        Button(role: nil) {
            Haptics.tap()
            onEdit()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(option.color.opacity(0.13))
                        .frame(width: 38, height: 38)
                    Image(systemName: option.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(option.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)

                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                    if dynamicTypeSize.isAccessibilitySize {
                        amount
                    }
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                    amount
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(metadata)，\(transaction.kind.displayName) \(FinanceFormatting.signedAmount(transaction))")
        .accessibilityHint("轻点编辑，长按查看更多操作")
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

// MARK: - Summary

struct FinanceSummaryStrip: View {
    let totals: FinanceTotals

    var body: some View {
        SurfaceCard(padding: 18) {
            HStack(spacing: 0) {
                column(
                    title: "支出",
                    value: MoneyFormatter.string(minorUnits: totals.expenseMinor, currencyCode: totals.currencyCode),
                    color: AppTheme.coral
                )

                Rectangle()
                    .fill(AppTheme.separator.opacity(0.7))
                    .frame(width: 0.8, height: 34)

                column(
                    title: "收入",
                    value: MoneyFormatter.string(minorUnits: totals.incomeMinor, currencyCode: totals.currencyCode),
                    color: AppTheme.accent
                )

                Rectangle()
                    .fill(AppTheme.separator.opacity(0.7))
                    .frame(width: 0.8, height: 34)

                column(
                    title: "结余",
                    value: MoneyFormatter.string(minorUnits: totals.balanceMinor, currencyCode: totals.currencyCode),
                    color: totals.balanceMinor >= 0 ? AppTheme.textPrimary : AppTheme.coral
                )
            }
        }
    }

    private func column(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Eyebrow(text: title, tint: AppTheme.textTertiary)
            Text(value)
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Horizontal summary carousel

struct FinanceSummaryCarousel: View {
    let totals: FinanceTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline) {
                Text("本月总览")
                    .font(.headline)
                    .foregroundStyle(ArchiveTheme.ink)
                Spacer()
                Label("滑动查看", systemImage: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(ArchiveTheme.inkSoft)
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    card(
                        code: "EXPENSE",
                        title: "支出",
                        value: MoneyFormatter.string(minorUnits: totals.expenseMinor, currencyCode: totals.currencyCode),
                        footnote: "本月已归档",
                        tint: AppTheme.coral,
                        fill: ArchiveTheme.pinkWash
                    )
                    card(
                        code: "INCOME",
                        title: "收入",
                        value: MoneyFormatter.string(minorUnits: totals.incomeMinor, currencyCode: totals.currencyCode),
                        footnote: "本月已入账",
                        tint: ArchiveTheme.mintDeep,
                        fill: ArchiveTheme.mintWash
                    )
                    card(
                        code: "BALANCE",
                        title: "结余",
                        value: MoneyFormatter.string(minorUnits: totals.balanceMinor, currencyCode: totals.currencyCode),
                        footnote: totals.balanceMinor >= 0 ? "本月收入减支出" : "本月支出超出收入",
                        tint: totals.balanceMinor >= 0 ? ArchiveTheme.gold : AppTheme.coral,
                        fill: ArchiveTheme.goldWash
                    )
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private func card(
        code: String,
        title: String,
        value: String,
        footnote: String,
        tint: Color,
        fill: Color
    ) -> some View {
        MangaPanel(fill: fill, padding: 14) {
            VStack(alignment: .leading, spacing: 7) {
                MangaCaptionTag(text: code, fill: tint, textColor: ArchiveTheme.ink)

                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .foregroundStyle(ArchiveTheme.ink)

                Text(value)
                    .font(.system(.title3, design: .serif).weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(ArchiveTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                ArchiveDashedRule()

                Text(footnote)
                    .font(.archiveMono)
                    .foregroundStyle(ArchiveTheme.inkSoft)
            }
        }
        .frame(width: 236)
        .containerRelativeFrame(.horizontal, count: 10, span: 7, spacing: 10)
    }
}
