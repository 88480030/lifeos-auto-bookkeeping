import Foundation
import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var selectedTab: AppTab
    var now: Date = .now

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \MoneyTransaction.occurredAt, order: .reverse)
    private var transactions: [MoneyTransaction]

    @Query(sort: \StudySession.startedAt, order: .reverse)
    private var sessions: [StudySession]

    @Query(sort: \ScheduleTask.startAt)
    private var tasks: [ScheduleTask]

    @Query(sort: \StudyTask.createdAt)
    private var studyTasks: [StudyTask]

    @Namespace private var coverNamespace
    @GestureState private var coverDrag: CGSize = .zero
    @State private var compactSummaryVisible = false
    @State private var companionReaction = 0
    @State private var companionMessage: String?
    @ObservedObject private var artwork = MiraArtStore.shared
    @State private var showingSettings = false
    @AppStorage("home.coverMode") private var coverModeRaw = HomeMode.daily.rawValue

    private var dashboard: HomeDashboard {
        HomeDashboard(transactions: transactions, sessions: sessions, tasks: tasks, now: now)
    }

    private var coverMode: HomeMode {
        HomeMode(rawValue: coverModeRaw) ?? .daily
    }

    private var missionCode: String {
        String(format: "%03d", Calendar.current.component(.day, from: dashboard.now))
    }

    private var todayStudyMinutes: Int {
        dashboard.todayStudyMinutes
    }

    private var unfinishedTaskCount: Int {
        max(0, dashboard.todayTaskCount - dashboard.completedTaskCount)
    }

    private var heroExpression: MiraExpression {
        if coverMode != .daily {
            return coverMode.expression
        }
        if dashboard.todayTaskCount == 0
            && dashboard.todayTransactions.isEmpty
            && todayStudyMinutes == 0 {
            return .thinking
        }
        if dashboard.todayTaskCount > 0, unfinishedTaskCount == 0 {
            return .happy
        }
        if unfinishedTaskCount >= 2 {
            return .alert
        }
        if todayStudyMinutes > 0 {
            return .focus
        }
        return .neutral
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ArchiveBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        homeHeader
                        coverPanel
                        DailySpendingPanel(transactions: transactions, date: now)
                        reportPanel
                        nextUpSection
                        fieldKitSection
                        intelligencePanel
                        if coverMode == .rest { offDutyPanel }
                        footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 140)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: HomeScrollOffsetKey.self,
                                value: proxy.frame(in: .named("homeScroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "homeScroll")
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(initialScrollAnchor)

            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if compactSummaryVisible {
                    compactHeader
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) { AppSettingsView() }
            .onPreferenceChange(HomeScrollOffsetKey.self) { value in
                // Hysteresis prevents the inset changing its own threshold.
                if value < -390 { compactSummaryVisible = true }
                if value > -200 { compactSummaryVisible = false }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: compactSummaryVisible)
            .onChange(of: dashboard.completedTaskCount) { previous, current in
                if current > previous {
                    companionReaction += 1
                    companionMessage = "又完成一项，今天的行动在推进。"
                }
            }
            .onChange(of: coverMode) { _, _ in companionMessage = nil }
            .task(id: companionMessage) {
                guard companionMessage != nil else { return }
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                companionMessage = nil
            }
            .onAppear {
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "-coverMode"),
                   arguments.indices.contains(index + 1),
                   HomeMode(rawValue: arguments[index + 1]) != nil {
                    coverModeRaw = arguments[index + 1]
                }
                #endif

            }
        }
    }

    // MARK: - Debug

    private var initialScrollAnchor: UnitPoint {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-scrollBottom") {
            return .bottom
        }
        if ProcessInfo.processInfo.arguments.contains("-scrollMissions") {
            return .center
        }
        #endif
        return .top
    }

    // MARK: - Cover

    private var homeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今天，也照顾好自己")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ArchiveTheme.ink)
                Text(AppFormatters.dateHeader(now))
                    .font(.subheadline)
                    .foregroundStyle(ArchiveTheme.inkSoft)
            }
            Spacer(minLength: 0)
            Button { showingSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ArchiveTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(ArchiveTheme.paperRaised, in: Circle())
                    .overlay(Circle().strokeBorder(ArchiveTheme.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("外观与应用设置")
        }
    }

    private var coverPanel: some View {
        MangaPanel(fill: coverMode.fill, borderWidth: 2, padding: 14, hardShadow: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("LIFEOS · \(missionCode)")
                            .font(.archiveMonoStrong)
                            .foregroundStyle(ArchiveTheme.inkSoft)
                        Text(coverHeadline)
                            .font(.system(.title2, design: .rounded).weight(.black))
                            .foregroundStyle(ArchiveTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(companionMessage ?? briefingText)
                            .font(.subheadline)
                            .foregroundStyle(ArchiveTheme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                        Button(action: openModeAction) {
                            HStack(spacing: 6) {
                                Text(modeActionTitle)
                                Image(systemName: "arrow.right")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ArchiveTheme.ink)
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(DepthPressStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 0) {
                            if artwork.customImage == nil {
                                LayeredCompanionView(
                                    character: .mira,
                                    mood: coverMode == .focus ? .focus : (coverMode == .rest ? .rest : .ready),
                                    reactionTrigger: companionReaction,
                                    onReact: {
                                        companionMessage = coverMode == .focus ? "准备好了？我们从一件事开始。" : coverMode == .rest ? "收到，陪你放松一下。" : "今天的档案，就交给我们一起整理。"
                                    }
                                )
                                .frame(width: 132, height: 160)
                            } else {
                                MangaCharacterImage(expression: heroExpression, width: 132, height: 160)
                            }
                            Text(artwork.customImage == nil ? "点我打个招呼" : "你的情报官")
                                .font(.caption2)
                                .foregroundStyle(ArchiveTheme.inkSoft)
                        }
                        .frame(width: 136, height: 180)
                    }
                }
                modeDots
            }
        }
        .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(max(-4, min(4, -coverDrag.height / 24)))), axis: (x: 1, y: 0, z: 0))
        .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(max(-4, min(4, coverDrag.width / 24)))), axis: (x: 0, y: 1, z: 0))
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .updating($coverDrag) { value, state, _ in
                    guard !reduceMotion,
                          abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                    state = value.translation
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 45 else { return }
                    cycleCoverMode(forward: value.translation.width < 0)
                }
        )
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: coverDrag)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: coverMode)
    }

    private var coverHeadline: String {
        switch coverMode {
        case .daily: "今天，按自己的节奏"
        case .focus: "留一段时间给专注"
        case .rest: "留一点空白，好好休息"
        }
    }

    private var modeActionTitle: String {
        switch coverMode {
        case .daily: "安排下一件事"
        case .focus: "打开专注计时"
        case .rest: "回顾今天的记录"
        }
    }

    private func openModeAction() {
        Haptics.tap()
        switch coverMode {
        case .daily: AppNavigationCenter.shared.open(.newSchedule)
        case .focus: AppNavigationCenter.shared.open(.studyFocus)
        case .rest: selectedTab = .assistant
        }
    }

    private var modeDots: some View {
        HStack(spacing: 4) {
            ForEach(HomeMode.allCases) { mode in
                Button {
                    Haptics.select()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
                        coverModeRaw = mode.rawValue
                    }
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(coverMode == mode ? .bold : .medium))
                        .foregroundStyle(coverMode == mode ? ArchiveTheme.stripInk : ArchiveTheme.inkSoft)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if coverMode == mode {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(ArchiveTheme.strip)
                                    .matchedGeometryEffect(id: "coverModeSelection", in: coverNamespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(coverMode == mode ? .isSelected : [])
            }
        }
        .padding(3)
        .background(ArchiveTheme.paperRaised.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    private func cycleCoverMode(forward: Bool) {
        Haptics.select()
        let modes = HomeMode.allCases
        let current = modes.firstIndex(of: coverMode) ?? 0
        let next = forward
            ? (current + 1) % modes.count
            : (current - 1 + modes.count) % modes.count
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            coverModeRaw = modes[next].rawValue
        }
    }

    private var briefingText: String {
        if coverMode != .daily {
            return coverMode.briefing
        }
        if dashboard.todayTaskCount > 0, unfinishedTaskCount > 0 {
            return "特工，今天还有 \(unfinishedTaskCount) 项行动未完成。"
        }

        if let next = dashboard.nextTask {
            return "下一项行动 \(AppFormatters.time(next.startAt))：\(next.title)。"
        }

        if todayStudyMinutes > 0 {
            return "今天已训练 \(todayStudyMinutes) 分钟，继续保持。"
        }

        if dashboard.todayTransactions.isEmpty {
            return "档案还是空的，先记下今天的第一笔。"
        }

        return "今天的行动已完成，MIRA 在整理档案。"
    }

    // MARK: - Sticky compact header

    private var compactHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今日行动 \(dashboard.completedTaskCount)/\(dashboard.todayTaskCount)")
                    .font(.subheadline.weight(.bold))
                Text("学习 \(todayStudyMinutes) 分钟 · 支出 \(todaySpendText)")
                    .font(.caption)
                    .foregroundStyle(ArchiveTheme.inkSoft)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: openModeAction) {
                Image(systemName: coverMode == .focus ? "play.fill" : coverMode == .rest ? "text.badge.checkmark" : "plus")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 44, height: 44)
                    .background(ArchiveTheme.mintWash, in: Circle())
            }
            .buttonStyle(DepthPressStyle())
            .accessibilityLabel(modeActionTitle)
        }
        .foregroundStyle(ArchiveTheme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ArchiveTheme.paperRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(ArchiveTheme.rule).frame(height: 1) }
    }

    // MARK: - Mission carousel

    private var reportPanel: some View {
        MangaPanel(fill: ArchiveTheme.paperRaised, borderWidth: 1.5, hardShadow: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("今日进度").font(.headline)
                    Spacer()
                    Text("实时记录").font(.caption).foregroundStyle(ArchiveTheme.inkSoft)
                }
                Group {
                    if dynamicTypeSize >= .xxxLarge {
                        VStack(alignment: .leading, spacing: 14) { overviewMetrics }
                    } else {
                        HStack(alignment: .top, spacing: 12) { overviewMetrics }
                    }
                }
                if let extra = extraCurrencyText {
                    Text(extra).font(.caption).foregroundStyle(ArchiveTheme.inkSoft)
                }
            }
            .foregroundStyle(ArchiveTheme.ink)
        }
    }

    @ViewBuilder
    private var overviewMetrics: some View {
        overviewMetric("学习分钟", value: "\(todayStudyMinutes)", icon: "book", tint: ArchiveTheme.mintDeep) {
            AppNavigationCenter.shared.open(.studyFocus)
        }
        overviewMetric("完成日程", value: "\(dashboard.completedTaskCount)/\(dashboard.todayTaskCount)", icon: "checkmark.circle", tint: ArchiveTheme.gold, progress: dashboard.todayTaskCount > 0 ? Double(dashboard.completedTaskCount) / Double(dashboard.todayTaskCount) : 0) {
            AppNavigationCenter.shared.open(.scheduleToday)
        }
    }

    private func overviewMetric(_ title: String, value: String, icon: String, tint: Color, progress: Double? = nil, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(ArchiveTheme.inkSoft)
                    .lineLimit(1)
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(ArchiveTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                GeometryReader { geometry in
                    Rectangle().fill(tint.opacity(0.16))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(tint.opacity(0.75))
                                .frame(width: geometry.size.width * min(1, max(0, progress ?? 1)))
                        }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DepthPressStyle())
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(value)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("打开对应档案")
    }

    private var todaySpendText: String {
        if let total = dashboard.todayExpenseTotals.first {
            return MoneyFormatter.string(
                minorUnits: total.minorUnits,
                currencyCode: total.currencyCode
            )
        }
        return MoneyFormatter.string(minorUnits: 0, currencyCode: "CNY")
    }

    private var extraCurrencyText: String? {
        let others = dashboard.todayExpenseTotals.dropFirst()
        guard !others.isEmpty else { return nil }
        return others.map { total in
            "\(CurrencyCatalog.displayName(for: total.currencyCode)) "
                + MoneyFormatter.string(
                    minorUnits: total.minorUnits,
                    currencyCode: total.currencyCode
                )
        }
        .joined(separator: "  ·  ")
    }

    private var offDutyPanel: some View {
        MangaPanel(
            fill: ArchiveTheme.pinkWash,
            borderWidth: 2.2,
            rotation: -0.55
        ) {
            ZStack(alignment: .topLeading) {
                MangaGingham(color: ArchiveTheme.coral, opacity: 0.06, cell: 20)

                VStack(alignment: .leading, spacing: 10) {
                    MangaSectionHeading(
                        code: "OFF DUTY",
                        title: "任务之外",
                        trailing: "HOME LOG",
                        accent: ArchiveTheme.pink
                    )

                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("任务之外，也要好好生活。")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(ArchiveTheme.ink)

                        Text(offDutyText)
                            .font(.archiveCaption)
                            .foregroundStyle(ArchiveTheme.inkSoft)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image("MascotOtter")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 70, height: 70)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(ArchiveTheme.ink, lineWidth: 1.2)
                        )
                        .accessibilityLabel("小水獭插画")

                    HStack(spacing: 5) {
                        mangaProp("cup.and.saucer.fill", tint: ArchiveTheme.gold)
                        mangaProp("leaf.fill", tint: ArchiveTheme.mintDeep)
                        mangaProp("sun.max.fill", tint: ArchiveTheme.coral)
                    }
                    }
                }
            }
        }
    }

    private var offDutyText: String {
        if todayStudyMinutes > 0 {
            return "今天已训练 \(todayStudyMinutes) 分钟。任务之外，也给自己留一点空白。"
        }
        return "今天还没有训练记录。泡杯茶，整理一下桌面，再开始也不迟。"
    }

    private func mangaProp(_ icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ArchiveTheme.paperRaised.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(ArchiveTheme.ink.opacity(0.5), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    // MARK: - Next up

    private var nextUpSection: some View {
        Group {
            if let task = dashboard.nextTask {
                Button {
                    Haptics.tap()
                    AppNavigationCenter.shared.open(.scheduleToday, scheduleDate: task.startAt)
                } label: {
                    MangaPanel(fill: ArchiveTheme.strip, borderWidth: 1.5, padding: 14, hardShadow: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(task.startAt <= now ? "计划进行中" : "接下来 · " + (AppFormatters.isToday(task.startAt) ? "今天" : AppFormatters.shortDate(task.startAt)))
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text(AppFormatters.time(task.startAt))
                                    .font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title).font(.headline).lineLimit(2)
                                    Text("\(AppFormatters.duration(minutes: task.durationMinutes)) · \(task.priority.displayName)优先级")
                                        .font(.caption).foregroundStyle(ArchiveTheme.stripInk.opacity(0.8))
                                }
                            }
                        }
                        .foregroundStyle(ArchiveTheme.stripInk)
                    }
                }
                .buttonStyle(ArchivePressStyle())
                .accessibilityLabel("查看日程，\(AppFormatters.dateHeader(task.startAt))，\(AppFormatters.time(task.startAt))，\(task.title)")
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("接下来的时间，由你安排").font(.headline)
                        Text("还没有即将开始的日程").font(.subheadline).foregroundStyle(ArchiveTheme.inkSoft)
                    }
                    Spacer(minLength: 0)
                    Button { AppNavigationCenter.shared.open(.newSchedule) } label: {
                        Image(systemName: "plus").font(.headline)
                            .frame(width: 44, height: 44)
                            .background(ArchiveTheme.mintWash, in: Circle())
                    }
                    .buttonStyle(ArchivePressStyle())
                    .accessibilityLabel("新建日程")
                }
                .foregroundStyle(ArchiveTheme.ink)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Field kit

    private var fieldKitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快速开始").font(.headline).foregroundStyle(ArchiveTheme.ink)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                        spacing: 8
                    ) {
                        fieldKitButtons
                    }
                } else {
                    HStack(spacing: 8) {
                        fieldKitButtons
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var fieldKitButtons: some View {
        MangaToolButton(icon: "square.and.pencil", title: "记一笔", tint: ArchiveTheme.coral) {
            QuickCaptureCenter.shared.present()
        }

        MangaToolButton(icon: "timer", title: "开始训练", tint: ArchiveTheme.mintDeep) {
            AppNavigationCenter.shared.open(.studyFocus)
        }

        MangaToolButton(icon: "plus.circle", title: "新行动", tint: ArchiveTheme.gold) {
            AppNavigationCenter.shared.open(.newSchedule)
        }

        MangaToolButton(icon: "sparkles", title: "情报官", tint: ArchiveTheme.inkSoft) {
            selectedTab = .assistant
        }
    }

    // MARK: - Intelligence

    private var intelligencePanel: some View {
        HomeBriefPanel(
            snapshot: DailyBriefSnapshot(
                transactions: transactions, sessions: sessions,
                scheduleTasks: tasks, studyTasks: studyTasks, now: now
            ),
            now: now,
            onOpenBrief: { AppNavigationCenter.shared.openBrief($0) },
            onPrimaryAction: { topic in
                switch topic {
                case .today:
                    if dashboard.todayTaskCount == 0 {
                        AppNavigationCenter.shared.open(.newSchedule)
                    } else {
                        AppNavigationCenter.shared.open(.scheduleToday, scheduleDate: now)
                    }
                case .finance: QuickCaptureCenter.shared.present()
                case .study: AppNavigationCenter.shared.open(.studyFocus)
                }
            }
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            Text("TO BE CONTINUED")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .italic()
                .foregroundStyle(ArchiveTheme.ink)

            Text("LIFEOS · CLASSIFIED  /  PAGE 01  /  YOUR EYES ONLY")
                .font(.archiveMono)
                .tracking(0.7)
                .foregroundStyle(ArchiveTheme.inkMuted)

        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}


enum HomeMode: String, CaseIterable, Identifiable {
    case daily
    case focus
    case rest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "日常模式"
        case .focus: "专注模式"
        case .rest: "休息模式"
        }
    }

    var heroTitle: String {
        switch self {
        case .daily: "DAILY BRIEF"
        case .focus: "FOCUS DRILL"
        case .rest: "OFF DUTY"
        }
    }

    var reportLine: String {
        switch self {
        case .daily: "CLASSIFIED · MISSION REPORT: 2026"
        case .focus: "TRAINING · MISSION REPORT: FOCUS"
        case .rest: "PRIVATE · MISSION REPORT: REST"
        }
    }

    var briefing: String {
        switch self {
        case .daily: "特工，今天还有 2 项行动未完成。"
        case .focus: "专注模式：先拿下今天的训练，再处理其他档案。"
        case .rest: "休息模式：任务之外，也要好好生活。"
        }
    }

    var fill: Color {
        switch self {
        case .daily: ArchiveTheme.sage
        case .focus: ArchiveTheme.mintWash
        case .rest: ArchiveTheme.pinkWash
        }
    }

    var expression: MiraExpression {
        switch self {
        case .daily: .alert
        case .focus: .focus
        case .rest: .happy
        }
    }
}

private struct HomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
