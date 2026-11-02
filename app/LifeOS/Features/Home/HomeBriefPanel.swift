import SwiftUI

/// 首页保留摘要与下一步；完整明细由情报页接续。
struct HomeBriefPanel: View {
    let snapshot: DailyBriefSnapshot
    let now: Date
    let onOpenBrief: (BriefTopic) -> Void
    let onPrimaryAction: (BriefTopic) -> Void

    @State private var topic: BriefTopic = .today
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var selectionNamespace

    var body: some View {
        MangaPanel(fill: ArchiveTheme.paperRaised, borderWidth: 1.2, padding: 18, hardShadow: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("今日简报").font(.title3.weight(.bold))
                    Spacer(minLength: 8)
                    Text(now, format: .dateTime.month().day())
                        .font(.caption).foregroundStyle(ArchiveTheme.inkSoft)
                }
                selector
                contentLayout {
                    Image(systemName: topic.symbol)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(ArchiveTheme.ink)
                        .frame(width: 58, height: 58)
                        .background(wash, in: RoundedRectangle(cornerRadius: 16))
                        .rotation3DEffect(.degrees(reduceMotion ? 0 : (topic == .finance ? -10 : topic == .study ? 10 : 0)), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: topic)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(headline).font(.headline)
                        Text(detail).font(.subheadline).foregroundStyle(ArchiveTheme.inkSoft)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 86, alignment: .leading)
                Divider().overlay(ArchiveTheme.rule)
                metricsLayout {
                    switch topic {
                    case .today:
                        metric("待办日程", value: "\(snapshot.pendingScheduleCount) 项", symbol: "calendar")
                        metric("已经完成", value: "\(snapshot.completedScheduleCount) 项", symbol: "checkmark.circle")
                    case .finance:
                        metric("今日支出", value: moneySummary(snapshot.expenseTotals), symbol: "arrow.up.right")
                        metric("今日收入", value: moneySummary(snapshot.incomeTotals), symbol: "arrow.down.left")
                    case .study:
                        metric("专注时间", value: "\(snapshot.studyTotals.minutes) 分钟", symbol: "clock")
                        metric("完成番茄", value: "\(snapshot.studyTotals.pomodoroCount) 个", symbol: "timer")
                    }
                }
                actionsLayout {
                    Button { Haptics.tap(); onPrimaryAction(topic) } label: {
                        Label(actionTitle, systemImage: actionSymbol)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 10)
                            .foregroundStyle(ArchiveTheme.stripInk)
                            .background(ArchiveTheme.strip, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(DepthPressStyle())
                    .accessibilityIdentifier("home.brief.primary")
                    Button { Haptics.tap(); onOpenBrief(topic) } label: {
                        Label("完整简报", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(DepthPressStyle())
                    .accessibilityIdentifier("home.dailyBrief")
                }
            }
            .foregroundStyle(ArchiveTheme.ink)
        }
    }

    private var selector: some View {
        actionsLayout {
            ForEach(BriefTopic.allCases) { candidate in
                Button {
                    guard topic != candidate else { return }
                    Haptics.select()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84)) { topic = candidate }
                } label: {
                    Label(candidate == .today ? "总览" : candidate.rawValue, systemImage: candidate.symbol)
                        .font(.subheadline.weight(topic == candidate ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if topic == candidate {
                                RoundedRectangle(cornerRadius: 10).fill(wash)
                                    .matchedGeometryEffect(id: "homeTopic", in: selectionNamespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(DepthPressStyle())
                .accessibilityAddTraits(topic == candidate ? .isSelected : [])
                .accessibilityIdentifier("home.brief.topic.\(candidate == .today ? "today" : candidate == .finance ? "finance" : "study")")
            }
        }
        .padding(4)
        .background(ArchiveTheme.paper, in: RoundedRectangle(cornerRadius: 14))
    }

    private var contentLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
    }
    private var metricsLayout: AnyLayout {
        dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    }
    private var actionsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: 6))
    }
    private var wash: Color {
        switch topic {
        case .today: ArchiveTheme.mintWash
        case .finance: ArchiveTheme.goldWash
        case .study: ArchiveTheme.pinkWash
        }
    }
    private var headline: String {
        switch topic {
        case .today:
            if snapshot.overdueScheduleCount > 0 { return "有 \(snapshot.overdueScheduleCount) 项安排待确认" }
            if snapshot.pendingScheduleCount > 0 { return "今天还有 \(snapshot.pendingScheduleCount) 项安排" }
            return snapshot.todayTasks.isEmpty ? "留点空间，安排下一件事" : "今天的日程都完成了"
        case .finance:
            return snapshot.todayTransactions.isEmpty ? "今天的账页还是空白" : "今天记录了 \(snapshot.todayTransactions.count) 笔收支"
        case .study:
            return snapshot.studyTotals.minutes == 0 ? "给今天留一段专注" : "今天已专注 \(snapshot.studyTotals.minutes) 分钟"
        }
    }
    private var detail: String {
        switch topic {
        case .today: return snapshot.overdueScheduleCount > 0 ? "计划时间已过，看看是否完成，或重新安排。" : "打开待办，选择眼前最适合推进的一件事。"
        case .finance: return snapshot.expenseTotals.count > 1 || snapshot.incomeTotals.count > 1 ? "各币种独立汇总，完整简报里可以逐项查看。" : "记下小额花费，让每天的消费都有迹可循。"
        case .study: return snapshot.pendingStudyTasks.first.map { "学习待办：\($0.title)" } ?? "先选一个小目标，小水獭陪你专注。"
        }
    }
    private var actionTitle: String {
        switch topic {
        case .today: snapshot.todayTasks.isEmpty ? "安排一件事" : "查看待办"
        case .finance: "记一笔"
        case .study: "开始专注"
        }
    }
    private var actionSymbol: String {
        switch topic {
        case .today: "calendar.badge.plus"
        case .finance: "plus"
        case .study: "play.fill"
        }
    }
    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(ArchiveTheme.inkSoft)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
    private func moneySummary(_ totals: [MoneyMath.CurrencyTotal]) -> String {
        guard let total = totals.first else { return "暂无记录" }
        guard totals.count == 1 else { return "\(totals.count) 种币种" }
        return MoneyFormatter.string(minorUnits: total.minorUnits, currencyCode: total.currencyCode)
    }
}
