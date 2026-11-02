import SwiftUI

struct FinanceRecordsView: View {
    private enum KindFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case expense = "支出"
        case income = "收入"

        var id: String { rawValue }

        func includes(_ kind: TransactionKind) -> Bool {
            switch self {
            case .all: true
            case .expense: kind == .expense
            case .income: kind == .income
            }
        }
    }

    let transactions: [MoneyTransaction]
    let month: Date
    let currencyCode: String
    @ObservedObject var categories: CustomCategoryStore
    let onEdit: (MoneyTransaction) -> Void
    let onDelete: (MoneyTransaction) -> Void
    let onAdd: () -> Void

    @State private var searchText = ""
    @State private var kindFilter = KindFilter.all
    @FocusState private var searchFocused: Bool

    /// Keep the summary scoped to the selected month and currency, independent of search.
    private var monthTransactions: [MoneyTransaction] {
        let interval = FinanceAnalytics.monthInterval(containing: month)
        return transactions.filter {
            $0.currencyCode.caseInsensitiveCompare(currencyCode) == .orderedSame
                && $0.occurredAt >= interval.start && $0.occurredAt < interval.end
        }
    }

    private var totals: FinanceTotals {
        FinanceAnalytics.totals(
            monthTransactions,
            in: FinanceAnalytics.monthInterval(containing: month),
            currencyCode: currencyCode
        )
    }

    private var searchTerms: [String] {
        searchText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private var isFiltering: Bool {
        !searchTerms.isEmpty || kindFilter != .all
    }

    private var filteredTransactions: [MoneyTransaction] {
        monthTransactions.filter { transaction in
            guard kindFilter.includes(transaction.kind) else { return false }
            let category = CategoryCatalog.option(
                for: transaction.categoryRaw,
                kind: transaction.kind,
                custom: categories.categories
            )
            let searchableText = [transaction.merchant, transaction.note, category.name, transaction.categoryRaw]
                .joined(separator: " ")
            return searchTerms.allSatisfy { term in
                searchableText.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    private var groups: [(day: Date, items: [MoneyTransaction])] {
        let calendar = Calendar.current
        var grouped: [Date: [MoneyTransaction]] = [:]
        for transaction in filteredTransactions {
            let day = calendar.startOfDay(for: transaction.occurredAt)
            grouped[day, default: []].append(transaction)
        }
        return grouped
            .map { (day: $0.key, items: $0.value.sorted { $0.occurredAt > $1.occurredAt }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            FinanceSummaryCarousel(totals: totals)

            if monthTransactions.isEmpty {
                SurfaceCard {
                    EmptyStateView(
                        icon: "creditcard",
                        title: "这个月还没有记录",
                        message: "点击右上角 +，记下第一笔真实收支。"
                    )
                    Button {
                        Haptics.tap()
                        onAdd()
                    } label: {
                        Text("记第一笔")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [AppTheme.goldBright, AppTheme.gold],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    }
                    .buttonStyle(PressableScaleStyle())
                    .padding(.top, 4)
                }
            } else {
                filters

                if groups.isEmpty {
                    SurfaceCard {
                        EmptyStateView(
                            icon: "magnifyingglass",
                            title: "没有符合条件的记录",
                            message: "试试商家、备注或分类中的其他关键词，或清除筛选查看本月全部记录。"
                        )
                        Button("清除筛选", action: resetFilters)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ArchiveTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(ArchiveTheme.mintWash))
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("finance.resetFilters")
                    }
                } else {
                    ForEach(groups, id: \.day) { group in
                        daySection(day: group.day, items: group.items)
                    }
                }
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ArchiveTheme.inkSoft)
                    .accessibilityHidden(true)

                TextField("搜索商家、备注或分类", text: $searchText)
                    .font(.subheadline)
                    .foregroundStyle(ArchiveTheme.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { searchFocused = false }
                    .accessibilityLabel("搜索本月记录")
                    .accessibilityIdentifier("finance.search")

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(ArchiveTheme.inkSoft)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索内容")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, searchText.isEmpty ? 14 : 0)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14).fill(ArchiveTheme.paperRaised))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ArchiveTheme.rule, lineWidth: 1))

            Picker("收支类型", selection: $kindFilter) {
                ForEach(KindFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("finance.kindFilter")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(isFiltering
                    ? "找到 \(filteredTransactions.count) 笔 / 本月 \(monthTransactions.count) 笔"
                    : "本月共 \(monthTransactions.count) 笔 · \(currencyCode)")
                    .font(.caption)
                    .foregroundStyle(ArchiveTheme.inkSoft)
                    .accessibilityIdentifier("finance.resultCount")

                Spacer(minLength: 0)

                if isFiltering {
                    Button("重置", action: resetFilters)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ArchiveTheme.ink)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("重置搜索和收支筛选")
                }
            }

            if isFiltering {
                Text("上方总览仍为本月全部收支，以下仅显示筛选结果。")
                    .font(.caption)
                    .foregroundStyle(ArchiveTheme.inkSoft)
            }
        }
        .onChange(of: kindFilter) { _, _ in searchFocused = false }
    }

    private func resetFilters() {
        searchText = ""
        kindFilter = .all
        searchFocused = false
    }

    private func daySection(day: Date, items: [MoneyTransaction]) -> some View {
        let dayExpense = items
            .filter { $0.kind == .expense }
            .reduce(0) { $0 + $1.amountMinor }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppFormatters.dateHeader(day))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                if dayExpense > 0 {
                    Text((isFiltering ? "结果支出 " : "支出 ") + MoneyFormatter.string(minorUnits: dayExpense, currencyCode: currencyCode))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(.horizontal, 4)

            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, transaction in
                        FinanceTransactionRow(
                            transaction: transaction,
                            categories: categories,
                            onEdit: { onEdit(transaction) },
                            onDelete: { onDelete(transaction) }
                        )

                        if index < items.count - 1 {
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
