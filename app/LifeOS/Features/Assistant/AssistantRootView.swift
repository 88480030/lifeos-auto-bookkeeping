import SwiftData
import SwiftUI

struct AssistantRootView: View {
    @Query(sort: \MoneyTransaction.occurredAt, order: .reverse) private var transactions: [MoneyTransaction]
    @Query(sort: \StudySession.startedAt, order: .reverse) private var sessions: [StudySession]
    @Query(sort: \ScheduleTask.startAt) private var scheduleTasks: [ScheduleTask]
    @Query(sort: \StudyTask.createdAt) private var studyTasks: [StudyTask]
    @State private var topic = BriefTopic.today
    @State private var showingSettings = false
    @State private var showingAIChat = false
    @State private var handledNavigationID: UUID?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let snapshot = DailyBriefSnapshot(
                    transactions: transactions, sessions: sessions,
                    scheduleTasks: scheduleTasks, studyTasks: studyTasks, now: timeline.date
                )
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            header.id("briefTop")
                            aiChatEntry
                            summaryPanel(snapshot, updatedAt: timeline.date)
                            Label("此简报在本机生成。", systemImage: "lock.shield")
                                .font(.footnote)
                                .foregroundStyle(ArchiveTheme.inkSoft)
                                .padding(.top, 4)
                            MangaPageFooter(page: "05")
                        }
                        .padding(.horizontal, AppTheme.pagePadding)
                        .padding(.top, 12)
                        .padding(.bottom, 150)
                    }
                    .scrollIndicators(.hidden)
                    .background(ArchiveBackground())
                    .foregroundStyle(ArchiveTheme.ink)
                    .onReceive(AppNavigationCenter.shared.$request) { request in
                        guard let request, request.action == .assistantBrief,
                              request.id != handledNavigationID else { return }
                        handledNavigationID = request.id
                        showingSettings = false
                        topic = request.briefTopic ?? .today
                        proxy.scrollTo("briefTop", anchor: .top)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) { AppSettingsView() }
            .sheet(isPresented: $showingAIChat) { AIChatView() }
        }
    }

    private var aiChatEntry: some View {
        Button { showingAIChat = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.title3).foregroundStyle(ArchiveTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(ArchiveTheme.paperRaised, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("和 AI 聊聊").font(.headline)
                    Text("聊目标、习惯，也可以按授权了解你的记录。")
                        .font(.subheadline).foregroundStyle(ArchiveTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.headline)
            }
            .foregroundStyle(ArchiveTheme.ink)
            .padding(16).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(ArchiveTheme.mintWash, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ai.chatEntry")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("专属情报官")
                    .font(.largeTitle.weight(.black))
                Text("把生活记录，变成下一步行动。")
                    .font(.subheadline)
                    .foregroundStyle(ArchiveTheme.inkSoft)
            }
            Spacer(minLength: 0)
            Button { showingSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(ArchiveTheme.paperRaised, in: Circle())
                    .overlay(Circle().strokeBorder(ArchiveTheme.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("外观与应用设置")
        }
    }

    private var topicFill: Color {
        switch topic {
        case .today: ArchiveTheme.mintWash
        case .finance: ArchiveTheme.goldWash
        case .study: ArchiveTheme.pinkWash
        }
    }

    private var topicAccent: Color {
        switch topic {
        case .today: ArchiveTheme.mintDeep
        case .finance: ArchiveTheme.gold
        case .study: ArchiveTheme.coral
        }
    }

    @ViewBuilder
    private func summaryPanel(_ snapshot: DailyBriefSnapshot, updatedAt: Date) -> some View {
        if topic == .today {
            BriefRemindersView(scheduleTasks: scheduleTasks, studyTasks: studyTasks, now: updatedAt) { topic = $0 }
        } else {
            detailSummaryPanel(snapshot, updatedAt: updatedAt)
        }
    }

    private func detailSummaryPanel(_ snapshot: DailyBriefSnapshot, updatedAt: Date) -> some View {
        MangaPanel(fill: topicFill, borderWidth: 1.6, hardShadow: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: topic.symbol)
                        .font(.title2.weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(topicAccent)
                        .frame(width: 44, height: 44)
                        .background(ArchiveTheme.paperRaised, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("你的记录，整理好了")
                            .font(.title3.weight(.bold))
                        Text(topicStatus(snapshot))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ArchiveTheme.inkSoft)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(BriefTopic.allCases) { candidate in
                            Button(candidate == .today ? "提醒事项" : "\(candidate.rawValue)摘要", systemImage: candidate.symbol) {
                                topic = candidate
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("切换摘要内容")
                }
                Text(summary(snapshot))
                    .font(.body)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(ArchiveTheme.rule)
                overviewLayout {
                    switch topic {
                    case .today:
                        overviewLabel("今日计划已完成", value: "\(snapshot.completedPlanCount)/\(snapshot.todayPlanCount)", icon: "checkmark.circle")
                        overviewLabel("已安排待办", value: "\(scheduleTasks.filter { !$0.isCompleted }.count + studyTasks.filter { !$0.isCompleted && $0.plannedDate != nil }.count) 项", icon: "calendar")
                    case .finance:
                        overviewLabel("今日支出", value: "\(snapshot.todayTransactions.filter { $0.kind == .expense }.count) 笔", icon: "arrow.up.right")
                        overviewLabel("今日收入", value: "\(snapshot.todayTransactions.filter { $0.kind == .income }.count) 笔", icon: "arrow.down.left")
                    case .study:
                        overviewLabel("学习待办", value: "\(snapshot.pendingStudyTasks.count) 项", icon: "book")
                        overviewLabel("今日番茄", value: "\(snapshot.studyTotals.pomodoroCount) 个", icon: "timer")
                    }
                }
                Divider().overlay(ArchiveTheme.rule)
                switch topic {
                case .today:
                    EmptyView()
                case .finance: financeContent(snapshot)
                case .study: studyContent(snapshot)
                }
                Text("本机记录 · \(AppFormatters.time(updatedAt)) 更新")
                    .font(.caption)
                    .foregroundStyle(ArchiveTheme.inkSoft)
            }
        }
    }

    private var overviewLayout: AnyLayout {
        dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 18))
    }

    private func overviewLabel(_ title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(topicAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(ArchiveTheme.inkSoft)
                Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func topicStatus(_ snapshot: DailyBriefSnapshot) -> String {
        switch topic {
        case .today:
            if snapshot.currentSchedule != nil { return "计划进行中" }
            if snapshot.todayPlanCount == 0 { return "今日尚未安排计划" }
            return snapshot.pendingPlanCount == 0 ? "今日计划已完成" : "还有 \(snapshot.pendingPlanCount) 项计划待完成"
        case .finance:
            return snapshot.todayTransactions.isEmpty ? "今日尚未记录收支" : "今日已记录 \(snapshot.todayTransactions.count) 笔收支"
        case .study:
            return "今天已专注 \(snapshot.studyTotals.minutes) 分钟"
        }
    }

    private func summary(_ snapshot: DailyBriefSnapshot) -> String {
        if let current = snapshot.currentSchedule {
            return "「\(current.title)」正在计划时段内。今天还有 \(snapshot.pendingScheduleCount) 项日程未完成，学习已累计 \(snapshot.studyTotals.minutes) 分钟。"
        }
        if snapshot.todayPlanCount == 0 && snapshot.todayTransactions.isEmpty && snapshot.studyTotals.minutes == 0 {
            let unplanned = snapshot.pendingStudyTasks.filter { $0.plannedDate == nil }.count
            if let next = snapshot.nextStudyTask, let date = next.plannedDate {
                return "今天没有已排期的计划，下一次学习在 \(AppFormatters.shortDate(date))。" + (unplanned > 0 ? "另有 \(unplanned) 项未排期待办。" : "")
            }
            if unplanned > 0 {
                return "今天没有已排期的计划。任务库中有 \(unplanned) 项未排期学习待办；选择关联任务不会自动把它安排到今天。"
            }
            return "今天的档案还是一张白纸。安排一件小事，或从一次专注开始。"
        }
        return "今天完成了 \(snapshot.completedPlanCount)/\(snapshot.todayPlanCount) 项计划（含学习任务），专注 \(snapshot.studyTotals.minutes) 分钟，记录了 \(snapshot.todayTransactions.count) 笔收支。给接下来的一件事留一点时间。"
    }

    private func financeContent(_ snapshot: DailyBriefSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("今日收支", detail: "\(snapshot.todayTransactions.count) 笔真实记录", icon: "creditcard")
            amountRows("支出", totals: snapshot.expenseTotals, tint: ArchiveTheme.coral)
            Divider().overlay(ArchiveTheme.rule)
            amountRows("收入", totals: snapshot.incomeTotals, tint: ArchiveTheme.mintDeep)
            Text("不同币种分别汇总，不进行汇率换算。月度预算和分类趋势可在记账中查看。")
                .font(.footnote).foregroundStyle(ArchiveTheme.inkSoft)
            navigationButton("查看记账明细", icon: "creditcard") { AppNavigationCenter.shared.open(.financeRecords) }
            navigationButton("记一笔", icon: "square.and.pencil") { QuickCaptureCenter.shared.present() }
        }
    }

    private func studyContent(_ snapshot: DailyBriefSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("从一件小事开始", detail: "今天专注 \(snapshot.studyTotals.minutes) 分钟", icon: "book.closed")
            if snapshot.pendingStudyTasks.isEmpty {
                Text("没有待完成的学习任务。你也可以直接开始一次自由专注。")
                    .font(.body).foregroundStyle(ArchiveTheme.inkSoft)
            } else {
                ForEach(Array(snapshot.pendingStudyTasks.prefix(3))) { task in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.title).font(.headline)
                        Text("\(task.subject.isEmpty ? "未分类" : task.subject) · 预计 \(task.estimatedMinutes) 分钟")
                            .font(.subheadline).foregroundStyle(ArchiveTheme.inkSoft)
                        if let date = task.plannedDate {
                            Text("计划 \(AppFormatters.shortDate(date))")
                                .font(.caption).foregroundStyle(ArchiveTheme.inkSoft)
                        }
                        navigationButton("专注这项任务", icon: "play.fill") {
                            AppNavigationCenter.shared.open(.studyFocus, studyTaskID: task.id)
                        }
                        Divider().overlay(ArchiveTheme.rule)
                    }
                }
            }
            navigationButton("打开番茄钟", icon: "timer") { AppNavigationCenter.shared.open(.studyFocus) }
        }
    }

    private func amountRows(_ title: String, totals: [MoneyMath.CurrencyTotal], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title).foregroundStyle(ArchiveTheme.ink)
            } icon: {
                Image(systemName: title == "支出" ? "arrow.up.right" : "arrow.down.left")
                    .foregroundStyle(tint)
            }
            .font(.headline)
            if totals.isEmpty {
                Text("暂无\(title)记录").font(.body).foregroundStyle(ArchiveTheme.inkSoft)
            } else {
                ForEach(totals) { total in
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(CurrencyCatalog.displayName(for: total.currencyCode)).font(.subheadline)
                            Spacer(minLength: 12)
                            Text(MoneyFormatter.string(minorUnits: total.minorUnits, currencyCode: total.currencyCode))
                                .font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(ArchiveTheme.ink)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(total.currencyCode).font(.subheadline)
                            Text(MoneyFormatter.string(minorUnits: total.minorUnits, currencyCode: total.currencyCode))
                                .font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(ArchiveTheme.ink)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(topicAccent)
                    .accessibilityHidden(true)
                Text(title).font(.title2.weight(.bold))
            }
            Text(detail).font(.subheadline).foregroundStyle(ArchiveTheme.inkSoft)
        }
    }

    private func navigationButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Label(title, systemImage: icon).font(.body.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.subheadline)
            }
            .foregroundStyle(ArchiveTheme.ink)
            .frame(minHeight: 44)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(ArchiveTheme.mintWash, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
