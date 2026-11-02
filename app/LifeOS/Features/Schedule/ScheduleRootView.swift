import Foundation
import SwiftUI
import SwiftData
import UIKit
import UserNotifications

struct ScheduleRootView: View {
    @StateObject private var reminderQueue = PlanReminderStatus.shared
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \ScheduleTask.startAt)
    private var tasks: [ScheduleTask]

    @Query(sort: \MoneyTransaction.occurredAt, order: .reverse)
    private var transactions: [MoneyTransaction]

    @Query(sort: \StudyTask.createdAt) private var studyTasks: [StudyTask]

    @State private var mode: ScheduleMode
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var showingEditor = false
    @State private var editingTask: ScheduleTask?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var didAutoOpenEditor = false
    @State private var searchText = ""
    @State private var statusFilter: ScheduleStatusFilter = .all
    @State private var pendingDeletion: ScheduleTask?
    @State private var errorMessage: String?
    @State private var handledNavigationID: UUID?

    #if DEBUG
    private let autoOpenEditor = ProcessInfo.processInfo.arguments.contains("-openScheduleTaskEditor")
    #endif

    init() {
        var initialMode: ScheduleMode = .day
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-scheduleMode"),
           arguments.indices.contains(index + 1),
           let parsed = ScheduleMode(rawValue: arguments[index + 1]) {
            initialMode = parsed
        }
        #endif
        _mode = State(initialValue: initialMode)
    }

    private var calendar: Calendar { Calendar.current }

    private var periodTitle: String {
        switch mode {
        case .day:
            return AppFormatters.dateHeader(selectedDate)
        case .week:
            let days = ScheduleCalendarHelper.weekDays(containing: selectedDate, calendar: calendar)
            guard let first = days.first, let last = days.last else { return "" }
            return "\(AppFormatters.shortDate(first)) – \(AppFormatters.shortDate(last))"
        case .month:
            return AppFormatters.monthTitle(selectedDate)
        }
    }

    private var tasksForSelectedDay: [ScheduleTask] {
        ScheduleAnalytics.tasks(tasks, on: selectedDate, calendar: calendar)
    }

    private var savedExpensesByDay: [Date: ScheduleExpenseDay] {
        ScheduleExpenseDay.grouped(transactions: transactions, calendar: calendar)
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || statusFilter != .all
    }

    private var matchingTasks: [ScheduleTask] {
        tasks.filter { SchedulePlanningHelper.matches($0, query: searchText) && statusFilter.includes($0) }
    }

    private var visibleTasksForSelectedDay: [ScheduleTask] {
        ScheduleAnalytics.tasks(matchingTasks, on: selectedDate, calendar: calendar)
    }

    private var periodTasks: [ScheduleTask] {
        let start: Date
        let end: Date
        switch mode {
        case .day:
            start = calendar.startOfDay(for: selectedDate)
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        case .week:
            start = ScheduleCalendarHelper.startOfWeek(selectedDate, calendar: calendar)
            end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        case .month:
            start = ScheduleCalendarHelper.startOfMonth(selectedDate, calendar: calendar)
            end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        }
        return tasks.filter { $0.startAt >= start && $0.startAt < end }
    }

    private var periodStudyTasks: [StudyTask] {
        studyTasks.filter { task in
            guard let date = task.plannedDate else { return false }
            switch mode {
            case .day: return calendar.isDate(date, inSameDayAs: selectedDate)
            case .week:
                let start = ScheduleCalendarHelper.startOfWeek(selectedDate, calendar: calendar)
                let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
                return date >= start && date < end
            case .month: return calendar.isDate(date, equalTo: selectedDate, toGranularity: .month)
            }
        }
    }
    private func studyMatches(_ task: StudyTask, filter: ScheduleStatusFilter) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (query.isEmpty || task.title.localizedCaseInsensitiveContains(query) || task.subject.localizedCaseInsensitiveContains(query)) &&
            (filter == .all || (filter == .completed ? task.isCompleted : !task.isCompleted))
    }
    private func planCount(_ filter: ScheduleStatusFilter) -> Int {
        queryMatchesInPeriod.filter { filter.includes($0) }.count + periodStudyTasks.filter { studyMatches($0, filter: filter) }.count
    }

    private var queryMatchesInPeriod: [ScheduleTask] {
        periodTasks.filter { SchedulePlanningHelper.matches($0, query: searchText) }
    }

    private var periodLabel: String {
        switch mode {
        case .day: "当天"
        case .week: "所选周"
        case .month: "所选月"
        }
    }

    private var nextTaskForSelectedDay: ScheduleTask? {
        SchedulePlanningHelper.nextTask(visibleTasksForSelectedDay)
    }

    private var todayTaskCount: Int {
        ScheduleAnalytics.tasks(tasks, on: .now, calendar: calendar).count + StudyPlanning.tasks(studyTasks, on: .now, calendar: calendar).count
    }

    private var subtitle: String {
        if let next = ScheduleAnalytics.nextTask(tasks) {
            let day = calendar.isDateInToday(next.startAt) ? "今天" : AppFormatters.shortDate(next.startAt)
            return "今天 \(todayTaskCount) 项 · 下一项 \(day) \(AppFormatters.time(next.startAt))"
        }
        return "今天 \(todayTaskCount) 项计划"
    }

    private var isTodaySelected: Bool {
        calendar.isDateInToday(selectedDate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        dateNavigator
                        ScheduleSegmentedControl(selection: $mode)
                        searchAndFilters
                        notificationBanner
                        content
                        studyPlanSection
                        MangaPageFooter(page: "04")
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.top, 10)
                    .padding(.bottom, 150)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingEditor) {
                ScheduleTaskEditorView(task: editingTask, defaultStart: defaultStartDate)
            }
            .onAppear(perform: onAppear)
            .onReceive(AppNavigationCenter.shared.$request) { request in
                guard let request, request.id != handledNavigationID,
                      request.action == .newSchedule || request.action == .scheduleToday else { return }
                handledNavigationID = request.id
                selectedDate = calendar.startOfDay(for: request.scheduleDate ?? .now)
                mode = .day
                resetFilters()
                if request.action == .newSchedule {
                    editingTask = nil
                    showingEditor = true
                }
            }
            .onChange(of: showingEditor) { _, isPresented in
                if !isPresented {
                    refreshNotificationState()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshNotificationState() }
            }
            .confirmationDialog("删除这个日程？", isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ), titleVisibility: .visible) {
                Button("删除日程", role: .destructive) {
                    if let task = pendingDeletion { delete(task) }
                    pendingDeletion = nil
                }
                Button("取消", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text(pendingDeletion.map { "“\($0.title)”将被删除。重复日程只删除这一次。" } ?? "")
            }
            .alert("操作未保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "请重试。")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                MangaCaptionTag(
                    text: "OPERATIONS",
                    fill: ArchiveTheme.ink,
                    rotation: -1.2
                )

                Text("行动日程")
                    .font(.system(.largeTitle, design: .rounded).weight(.black))
                    .foregroundStyle(ArchiveTheme.ink)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ArchiveTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button {
                Haptics.tap()
                editingTask = nil
                showingEditor = true
            } label: {
                ZStack {
                    Circle().fill(ArchiveTheme.mintWash)
                    Circle().strokeBorder(ArchiveTheme.ink, lineWidth: 1.5)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ArchiveTheme.ink)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(PressableScaleStyle())
            .accessibilityLabel("新建日程")
        }
    }

    private var dateNavigator: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(periodTitle)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())

            HStack(spacing: 8) {
                navButton(systemName: "chevron.left", label: "上一个\(mode.title)") { shift(-1) }
                navButton(systemName: "chevron.right", label: "下一个\(mode.title)") { shift(1) }
                Spacer(minLength: 4)
            Button {
                Haptics.select()
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    selectedDate = calendar.startOfDay(for: .now)
                }
            } label: {
                Text("今天")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isTodaySelected ? AppTheme.textSecondary : AppTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Capsule(style: .continuous).fill(AppTheme.surface.opacity(0.55)))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isTodaySelected ? AppTheme.separator.opacity(0.6) : AppTheme.gold.opacity(0.35),
                                lineWidth: 0.8
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(isTodaySelected)
            }
        }
    }

    private func navButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                action()
            }
        } label: {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(AppTheme.surface.opacity(0.55)))
                .overlay(Circle().strokeBorder(AppTheme.separator.opacity(0.7), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var searchAndFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityHidden(true)
                TextField("搜索标题或备注", text: $searchText)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .accessibilityLabel("搜索日程标题或备注")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, searchText.isEmpty ? 14 : 0)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.separator, lineWidth: 1))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ScheduleStatusFilter.allCases) { filter in
                        Button {
                            Haptics.select()
                            statusFilter = filter
                        } label: {
                            Text("\(filter.title) \(planCount(filter))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(statusFilter == filter ? AppTheme.accentSoft : AppTheme.surface))
                                .overlay(Capsule().strokeBorder(statusFilter == filter ? AppTheme.accent : AppTheme.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(statusFilter == filter ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(alignment: .center) {
                Text("\(periodLabel)显示 \(planCount(statusFilter)) / \(periodTasks.count + periodStudyTasks.count) 项\(mode == .day ? "" : " · 点选日期查看当天")")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if isFiltering {
                    Button("重置") { resetFilters() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("清除搜索与状态筛选")
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .day:
            ScheduleDayView(
                date: selectedDate,
                tasks: visibleTasksForSelectedDay,
                allTasks: tasksForSelectedDay,
                studyCounts: studyCounts,
                expensesByDay: savedExpensesByDay,
                nextTask: nextTaskForSelectedDay,
                isFiltering: isFiltering,
                onResetFilters: resetFilters,
                onEdit: beginEdit,
                onToggle: toggle,
                onDelete: requestDelete,
                onAdd: beginAdd,
                onOpenRecords: openSelectedDayRecords
            )
        case .week:
            ScheduleWeekView(
                selectedDate: $selectedDate,
                tasks: matchingTasks,
                allTasks: tasks,
                studyCounts: studyCounts,
                expensesByDay: savedExpensesByDay,
                isFiltering: isFiltering,
                onResetFilters: resetFilters,
                onEdit: beginEdit,
                onToggle: toggle,
                onDelete: requestDelete,
                onAdd: beginAdd,
                onOpenRecords: openSelectedDayRecords
            )
        case .month:
            ScheduleMonthView(
                selectedDate: $selectedDate,
                month: selectedDate,
                tasks: matchingTasks,
                allTasks: tasks,
                studyCounts: studyCounts,
                expensesByDay: savedExpensesByDay,
                isFiltering: isFiltering,
                onResetFilters: resetFilters,
                onEdit: beginEdit,
                onToggle: toggle,
                onDelete: requestDelete,
                onAdd: beginAdd,
                onOpenRecords: openSelectedDayRecords
            )
        }
    }

    private var studyCounts: [Date: Int] {
        var result: [Date: Int] = [:]
        for task in studyTasks {
            guard let date = task.plannedDate, studyMatches(task, filter: statusFilter) else { continue }
            result[calendar.startOfDay(for: date), default: 0] += 1
        }
        return result
    }

    @ViewBuilder private var studyPlanSection: some View {
        let planned = StudyPlanning.tasks(studyTasks, on: selectedDate, calendar: calendar)
            .filter { studyMatches($0, filter: statusFilter) }
            .sorted { ($0.plannedStartMinute ?? 1440) < ($1.plannedStartMinute ?? 1440) }
        if !planned.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppFormatters.shortDate(selectedDate) + " · 学习计划 \(planned.count) 项").font(.headline)
                Text("按开始时间排列；时间会保存，与学习页面保持一致。")
                    .font(.caption).foregroundStyle(ArchiveTheme.inkSoft)
                ForEach(planned) { task in
                    Button {
                        AppNavigationCenter.shared.open(.studyFocus, studyTaskID: task.id)
                    } label: {
                        HStack {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "book.closed")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title).font(.subheadline.weight(.semibold))
                                Text((task.plannedTimeRange ?? "待安排具体时间") + " · " + AppFormatters.duration(minutes: task.estimatedMinutes)).font(.caption)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }.padding(14).background(ArchiveTheme.mintWash, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var notificationBanner: some View {
        if notificationStatus == .denied {
            SurfaceCard(padding: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.coral)
                    Text("日程提醒未开启，锁屏时不会收到提醒。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button("去设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        } else if notificationStatus == .notDetermined {
            SurfaceCard(padding: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.gold)
                    Text("开启通知，日程会准时提醒")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer(minLength: 6)
                    Button("开启") {
                        enableNotifications()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Label("学习与生活日程 · 提前 15 分钟提醒", systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                if let message = reminderQueue.errorMessage {
                    Text(message).foregroundStyle(ArchiveTheme.coral)
                } else if let next = reminderQueue.nextFireAt {
                    Text("下一次提醒：" + AppFormatters.dateTime(next))
                    Text("已预排 \(reminderQueue.scheduledCount) 条，打开应用会自动续排。")
                } else {
                    Text("有具体开始时间的未来任务会自动排入提醒。")
                }
            }
            .font(.caption)
            .foregroundStyle(ArchiveTheme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private var defaultStartDate: Date {
        let day = calendar.startOfDay(for: selectedDate)
        if calendar.isDateInToday(selectedDate) {
            let now = Date()
            if let nextHour = calendar.date(
                bySettingHour: calendar.component(.hour, from: now) + 1,
                minute: 0,
                second: 0,
                of: day
            ), nextHour > now {
                return nextHour
            }
            return now
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    private func shift(_ direction: Int) {
        switch mode {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: direction, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .day, value: direction * 7, to: selectedDate) ?? selectedDate
        case .month:
            let base = ScheduleCalendarHelper.startOfMonth(selectedDate, calendar: calendar)
            let next = calendar.date(byAdding: .month, value: direction, to: base) ?? base
            selectedDate = ScheduleCalendarHelper.startOfMonth(next, calendar: calendar)
        }
    }

    private func beginAdd() {
        editingTask = nil
        showingEditor = true
    }

    private func openSelectedDayRecords() {
        Haptics.tap()
        AppNavigationCenter.shared.open(.financeRecords, scheduleDate: selectedDate)
    }

    private func resetFilters() {
        searchText = ""
        statusFilter = .all
    }

    private func requestDelete(_ task: ScheduleTask) {
        pendingDeletion = task
    }

    private func beginEdit(_ task: ScheduleTask) {
        editingTask = task
        showingEditor = true
    }

    private func toggle(_ task: ScheduleTask) {
        task.isCompleted.toggle()
        do {
            try context.save()
        } catch {
            task.isCompleted.toggle()
            errorMessage = "完成状态未能保存，请重试。"
            return
        }
        if task.isCompleted {
            ScheduleNotificationManager.cancel(taskID: task.id)
        }
        Task { await ScheduleNotificationManager.rescheduleAll(context: context) }
        Haptics.select()
    }

    private func delete(_ task: ScheduleTask) {
        let id = task.id
        context.delete(task)
        do {
            try context.save()
        } catch {
            context.rollback()
            errorMessage = "日程未能删除，请重试。"
            return
        }
        ScheduleNotificationManager.cancel(taskID: id)
        Task { await ScheduleNotificationManager.rescheduleAll(context: context) }
        Haptics.success()
    }

    private func onAppear() {
        refreshNotificationState()
        #if DEBUG
        if autoOpenEditor && !didAutoOpenEditor {
            didAutoOpenEditor = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                editingTask = nil
                showingEditor = true
            }
        }
        #endif
    }

    private func refreshNotificationState() {
        Task {
            notificationStatus = await ScheduleNotificationManager.authorizationStatus()
            if notificationStatus == .authorized
                || notificationStatus == .provisional
                || notificationStatus == .ephemeral {
                await ScheduleNotificationManager.rescheduleAll(context: context)
            }
        }
    }

    private func enableNotifications() {
        Task {
            _ = await ScheduleNotificationManager.requestPermissionIfNeeded()
            refreshNotificationState()
        }
    }
}
