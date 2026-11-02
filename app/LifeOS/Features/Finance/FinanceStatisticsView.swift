import SwiftUI
import Charts

struct FinanceStatisticsView: View {
    let allTransactions: [MoneyTransaction]
    let month: Date
    let currencyCode: String
    let budgets: [Budget]
    @ObservedObject var categories: CustomCategoryStore
    let onSetBudget: () -> Void
    let onEdit: (MoneyTransaction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var trendRange: TrendRange = .week
    @State private var selectedTrendDate: Date?
    @State private var selectedCategoryID: String?
    @State private var selectedCategoryAngle: Double?

    private enum TrendRange: String, CaseIterable, Identifiable {
        case week
        case month

        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: "本周"
            case .month: "本月"
            }
        }
    }

    private struct TrendPoint: Identifiable {
        let day: Date
        let minorUnits: Int
        var id: Date { day }
    }

    private struct CategorySlice: Identifiable {
        let categoryRaw: String
        let option: CategoryOption
        let minorUnits: Int
        var id: String { categoryRaw }
    }

    private let calendar = Calendar.current

    private var monthInterval: DateInterval {
        FinanceAnalytics.monthInterval(containing: month)
    }

    private var weekInterval: DateInterval {
        FinanceAnalytics.weekInterval(containing: .now)
    }

    private var todayTotals: FinanceTotals {
        FinanceAnalytics.totals(allTransactions, on: .now, currencyCode: currencyCode)
    }

    private var weekTotals: FinanceTotals {
        FinanceAnalytics.totals(allTransactions, in: weekInterval, currencyCode: currencyCode)
    }

    private var monthTotals: FinanceTotals {
        FinanceAnalytics.totals(allTransactions, in: monthInterval, currencyCode: currencyCode)
    }

    private var trendInterval: DateInterval {
        trendRange == .week ? weekInterval : monthInterval
    }

    private var trendPoints: [TrendPoint] {
        let daily = FinanceAnalytics.dailyExpenses(
            allTransactions,
            in: trendInterval,
            currencyCode: currencyCode,
            calendar: calendar
        )
        let lookup = Dictionary(uniqueKeysWithValues: daily.map { (calendar.startOfDay(for: $0.day), $0.minorUnits) })

        var points: [TrendPoint] = []
        var day = calendar.startOfDay(for: trendInterval.start)
        while day < trendInterval.end {
            points.append(TrendPoint(day: day, minorUnits: lookup[day] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }

    private var categorySlices: [CategorySlice] {
        FinanceAnalytics.categoryTotals(
            allTransactions,
            kind: .expense,
            in: monthInterval,
            currencyCode: currencyCode
        )
        .map { total in
            CategorySlice(
                categoryRaw: total.categoryRaw,
                option: CategoryCatalog.option(
                    for: total.categoryRaw,
                    kind: .expense,
                    custom: categories.categories
                ),
                minorUnits: total.minorUnits
            )
        }
    }

    private var monthKey: String {
        DayKey.monthKey(for: month)
    }

    private var budget: Budget? {
        budgets.first {
            $0.monthKey == monthKey
                && $0.currencyCode.uppercased() == currencyCode.uppercased()
        }
    }

    private var selectedTrendIndex: Int? {
        guard let selectedTrendDate else { return nil }
        return trendPoints.firstIndex { calendar.isDate($0.day, inSameDayAs: selectedTrendDate) }
    }

    private var selectedTrendPoint: TrendPoint? {
        guard let selectedTrendIndex else { return nil }
        return trendPoints[selectedTrendIndex]
    }

    private var selectedCategory: CategorySlice? {
        categorySlices.first { $0.id == selectedCategoryID }
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            metricRow
            trendCard
            categoryCard
            budgetCard
        }
        .onChange(of: trendRange) { _, _ in clearChartSelections() }
        .onChange(of: monthKey) { _, _ in clearChartSelections() }
        .onChange(of: currencyCode.uppercased()) { _, _ in clearChartSelections() }
        .onChange(of: selectedCategoryAngle) { _, angle in
            guard let angle else { return }
            selectCategory(at: angle)
        }
        .onChange(of: categorySlices.map(\.id)) { _, ids in
            if let selectedCategoryID, !ids.contains(selectedCategoryID) {
                self.selectedCategoryID = nil
                selectedCategoryAngle = nil
            }
        }
    }

    // MARK: - Metrics

    @ViewBuilder
    private var metricRow: some View {
        if dynamicTypeSize >= .xxxLarge {
            VStack(spacing: 10) {
                metricCards(compact: false)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    metricCards(compact: true)
                }
                VStack(spacing: 10) {
                    metricCards(compact: false)
                }
            }
        }
    }

    @ViewBuilder
    private func metricCards(compact: Bool) -> some View {
        metric(title: "今日支出", value: MoneyFormatter.string(minorUnits: todayTotals.expenseMinor, currencyCode: currencyCode), tint: AppTheme.coral, compact: compact)
        metric(title: "本周支出", value: MoneyFormatter.string(minorUnits: weekTotals.expenseMinor, currencyCode: currencyCode), tint: AppTheme.gold, compact: compact)
        metric(title: "本月支出", value: MoneyFormatter.string(minorUnits: monthTotals.expenseMinor, currencyCode: currencyCode), tint: AppTheme.indigo, compact: compact)
    }

    private func metric(title: String, value: String, tint: Color, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: compact, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.tileRadius, style: .continuous)
                .fill(AppTheme.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.tileRadius, style: .continuous)
                .strokeBorder(AppTheme.separator.opacity(0.7), lineWidth: 0.8)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Trend

    private var trendCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center) {
                        trendHeading
                        Spacer(minLength: 12)
                        trendPicker
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        trendHeading
                        trendPicker
                    }
                }

                if trendPoints.allSatisfy({ $0.minorUnits == 0 }) {
                    EmptyStateView(
                        icon: "chart.bar",
                        title: "暂无支出数据",
                        message: "添加几笔支出后，这里会自动生成趋势图。"
                    )
                } else {
                    trendSelectionReadout

                    Chart {
                        ForEach(trendPoints) { point in
                            let isEmphasized = selectedTrendPoint == nil || selectedTrendPoint?.id == point.id
                            BarMark(
                                x: .value("日期", point.day, unit: .day),
                                y: .value("支出", Double(point.minorUnits))
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        AppTheme.coral.opacity(isEmphasized ? 0.92 : 0.25),
                                        AppTheme.gold.opacity(isEmphasized ? 0.92 : 0.25)
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .cornerRadius(4)
                            .accessibilityLabel(Text(point.day.formatted(.dateTime.month().day())))
                            .accessibilityValue(Text(MoneyFormatter.string(minorUnits: point.minorUnits, currencyCode: currencyCode)))
                        }

                        if let point = selectedTrendPoint {
                            RuleMark(x: .value("选中日期", point.day, unit: .day))
                                .foregroundStyle(AppTheme.textSecondary.opacity(0.65))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .accessibilityHidden(true)
                        }
                    }
                    .chartXSelection(value: $selectedTrendDate)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: trendRange == .week ? 1 : 5)) { _ in
                            AxisValueLabel(format: .dateTime.day())
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 168)
                    .animation(selectionAnimation, value: selectedTrendPoint?.id)

                    Text("单位：\(currencyCode) · 每日支出")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    private var trendHeading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Eyebrow(text: "Trend")
            Text("支出趋势")
                .font(.lifeCard)
                .foregroundStyle(AppTheme.textPrimary)
        }
    }

    private var trendSelectionReadout: some View {
        HStack(spacing: 10) {
            trendStepButton(systemImage: "chevron.left", offset: -1)

            VStack(alignment: .leading, spacing: 4) {
                if let point = selectedTrendPoint {
                    Text(point.day.formatted(.dateTime.month().day().weekday(.abbreviated)))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(MoneyFormatter.string(minorUnits: point.minorUnits, currencyCode: currencyCode))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("选择日期查看支出")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("轻点柱形，或使用左右按钮")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            trendStepButton(systemImage: "chevron.right", offset: 1)
        }
    }

    private func trendStepButton(systemImage: String, offset: Int) -> some View {
        let canMove = selectedTrendIndex.map { trendPoints.indices.contains($0 + offset) } ?? !trendPoints.isEmpty

        return Button {
            let points = trendPoints
            let nextIndex = selectedTrendIndex.map { $0 + offset } ?? (offset < 0 ? points.count - 1 : 0)
            guard points.indices.contains(nextIndex) else { return }
            Haptics.select()
            withAnimation(selectionAnimation) {
                selectedTrendDate = points[nextIndex].day
            }
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(canMove ? AppTheme.textPrimary : AppTheme.textTertiary)
                .background(AppTheme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canMove)
        .accessibilityLabel(offset < 0 ? "向前查看日期" : "向后查看日期")
        .accessibilityHint(selectedTrendPoint == nil ? (offset < 0 ? "从最后一天开始" : "从第一天开始") : "逐日查看支出金额")
    }

    private var trendPicker: some View {
        HStack(spacing: 2) {
            ForEach(TrendRange.allCases) { range in
                Button {
                    guard trendRange != range else { return }
                    Haptics.select()
                    withAnimation(selectionAnimation) {
                        trendRange = range
                    }
                } label: {
                    Text(range.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(trendRange == range ? AppTheme.textPrimary : AppTheme.textTertiary)
                        .padding(.horizontal, 9)
                        .frame(minWidth: 44, minHeight: 44)
                        .background {
                            if trendRange == range {
                                Capsule(style: .continuous)
                                    .fill(AppTheme.surface.opacity(0.9))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(trendRange == range ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(AppTheme.surface.opacity(0.35)))
        .overlay(Capsule(style: .continuous).strokeBorder(AppTheme.separator.opacity(0.7), lineWidth: 0.8))
    }

    // MARK: - Category

    private var categoryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "Categories")
                        Text("分类占比")
                            .font(.lifeCard)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    if monthTotals.expenseMinor > 0 {
                        Text("本月总支出 " + MoneyFormatter.string(minorUnits: monthTotals.expenseMinor, currencyCode: currencyCode))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if categorySlices.isEmpty {
                    EmptyStateView(
                        icon: "chart.pie",
                        title: "暂无分类数据",
                        message: "本月还没有支出记录。"
                    )
                } else {
                    categorySelectionReadout
                    categoryBreakdown
                    Text("轻点环图或分类查看金额，再点已选分类可取消。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    private var categorySelectionReadout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedCategory.map { "\($0.option.name) · \(categoryPercentage($0))" } ?? "本月全部分类")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text(MoneyFormatter.string(minorUnits: selectedCategory?.minorUnits ?? monthTotals.expenseMinor, currencyCode: currencyCode))
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var categoryBreakdown: some View {
        let layout = dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))

        return layout {
            categoryChart
                .frame(maxWidth: dynamicTypeSize >= .xxxLarge ? .infinity : nil)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(categorySlices) { slice in
                    legendRow(slice)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var categoryChart: some View {
        Chart(categorySlices) { slice in
            SectorMark(
                angle: .value("金额", Double(slice.minorUnits)),
                innerRadius: .ratio(0.7),
                angularInset: 2
            )
            .cornerRadius(4)
            .foregroundStyle(slice.option.color.opacity(selectedCategory == nil || selectedCategory?.id == slice.id ? 1 : 0.25))
            .accessibilityLabel(Text(slice.option.name))
            .accessibilityValue(Text(MoneyFormatter.string(minorUnits: slice.minorUnits, currencyCode: currencyCode) + "，" + categoryPercentage(slice)))
        }
        .chartAngleSelection(value: $selectedCategoryAngle)
        .frame(width: 170, height: 170)
        .overlay {
            VStack(spacing: 4) {
                Text(selectedCategory?.option.name ?? "本月支出")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                Text(selectedCategory.map { categoryPercentage($0) } ?? "100%")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(width: 106)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .animation(selectionAnimation, value: selectedCategoryID)
    }

    private func legendRow(_ slice: CategorySlice) -> some View {
        let isSelected = selectedCategoryID == slice.id

        return Button {
            Haptics.select()
            withAnimation(selectionAnimation) {
                selectedCategoryAngle = nil
                selectedCategoryID = isSelected ? nil : slice.id
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(slice.option.color)
                    .frame(width: 9, height: 9)
                Text(slice.option.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(categoryPercentage(slice))
                    .font(.caption.monospacedDigit())
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(slice.option.color)
                }
            }
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(isSelected ? slice.option.color.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slice.option.name + "，" + MoneyFormatter.string(minorUnits: slice.minorUnits, currencyCode: currencyCode) + "，" + categoryPercentage(slice))
        .accessibilityHint(isSelected ? "取消分类选择" : "查看此分类")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func categoryPercentage(_ slice: CategorySlice) -> String {
        let fraction = monthTotals.expenseMinor > 0
            ? Double(slice.minorUnits) / Double(monthTotals.expenseMinor)
            : 0
        return fraction.formatted(.percent.precision(.fractionLength(0...1)))
    }

    private func selectCategory(at angle: Double) {
        guard angle.isFinite, angle >= 0 else { return }
        var upperBound = 0.0
        for (index, slice) in categorySlices.enumerated() {
            upperBound += Double(slice.minorUnits)
            if angle < upperBound || (index == categorySlices.count - 1 && angle == upperBound) {
                guard selectedCategoryID != slice.id else { return }
                Haptics.select()
                withAnimation(selectionAnimation) {
                    selectedCategoryID = slice.id
                }
                return
            }
        }
    }

    private func clearChartSelections() {
        selectedTrendDate = nil
        selectedCategoryID = nil
        selectedCategoryAngle = nil
    }

    // MARK: - Budget

    private var budgetCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "Budget")
                        Text("本月预算")
                            .font(.lifeCard)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    Spacer()
                    Button {
                        Haptics.tap()
                        onSetBudget()
                    } label: {
                        Text(budget == nil ? "设置" : "编辑")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.gold)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Capsule(style: .continuous).fill(AppTheme.gold.opacity(0.10)))
                            .overlay(Capsule(style: .continuous).strokeBorder(AppTheme.gold.opacity(0.30), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(budget == nil ? "设置本月预算" : "编辑本月预算")
                }

                if let budget {
                    let status = FinanceAnalytics.budgetStatus(
                        amountMinor: budget.amountMinor,
                        spentMinor: monthTotals.expenseMinor
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("已使用")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                        Text(MoneyFormatter.string(minorUnits: monthTotals.expenseMinor, currencyCode: currencyCode))
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(status.isOverBudget ? AppTheme.coral : AppTheme.textPrimary)
                        Text("预算 " + MoneyFormatter.string(minorUnits: budget.amountMinor, currencyCode: currencyCode))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)

                    ProgressBar(
                        progress: status.progress,
                        tint: status.isOverBudget ? AppTheme.coral : AppTheme.gold
                    )

                    Text(
                        status.isOverBudget
                            ? "已超出预算 " + MoneyFormatter.string(minorUnits: abs(status.remainingMinor), currencyCode: currencyCode)
                            : "剩余 " + MoneyFormatter.string(minorUnits: status.remainingMinor, currencyCode: currencyCode)
                    )
                    .font(.caption)
                    .foregroundStyle(status.isOverBudget ? AppTheme.coral : AppTheme.textSecondary)
                } else {
                    Text("还没有设置本月预算。设置后可以跟踪剩余额度并获得超支提醒。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
