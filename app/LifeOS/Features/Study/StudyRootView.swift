import Combine
import Foundation
import SwiftUI
import SwiftData

struct StudyRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @StateObject private var timer = StudyTimerEngine.shared

    @Query(sort: \StudySession.startedAt, order: .reverse)
    private var sessions: [StudySession]

    @Query(sort: \StudyTask.createdAt, order: .reverse)
    private var tasks: [StudyTask]

    @State private var section: StudySection
    @State private var selectedTaskID: UUID?
    @State private var showingTaskEditor = false
    @State private var editingTask: StudyTask?
    @State private var showingSettings = false
    @State private var didInitializeTask = false
    @State private var mutationError: String?
    @State private var handledNavigationID: UUID?

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    init() {
        var initialSection: StudySection = .timer
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-studySection"),
           arguments.indices.contains(index + 1),
           let parsed = StudySection(rawValue: arguments[index + 1]) {
            initialSection = parsed
        }
        #endif
        _section = State(initialValue: initialSection)
    }

    private var todayTotals: StudyTotals {
        StudyAnalytics.totals(sessions, on: .now)
    }

    private var streak: Int {
        StudyAnalytics.streak(sessions, now: .now)
    }

    private var goalProgress: Double {
        StudyAnalytics.goalProgress(
            focusedSeconds: todayTotals.focusedSeconds,
            dailyGoalMinutes: timer.preferences.dailyGoalMinutes
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            header.id("studyHeader")
                            StudySegmentedControl(selection: $section)
                            sectionContent
                            MangaPageFooter(page: "03")
                        }
                        .padding(.horizontal, AppTheme.pagePadding)
                        .padding(.top, 10)
                        .padding(.bottom, 150)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: section) { _, _ in
                        proxy.scrollTo("studyHeader", anchor: .top)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingTaskEditor) {
                StudyTaskEditorView(task: editingTask).id(editingTask?.id)
            }
            .sheet(isPresented: $showingSettings) {
                StudySettingsView(timer: timer)
            }
            .onAppear {
                timer.attach(context: context)
                initializeSelectedTaskIfNeeded()
            }
            .alert("学习任务未保存", isPresented: Binding(
                get: { mutationError != nil },
                set: { if !$0 { mutationError = nil } }
            )) {
                Button("知道了", role: .cancel) { mutationError = nil }
            } message: {
                Text(mutationError ?? "请稍后重试。")
            }
            .onReceive(AppNavigationCenter.shared.$request) { request in
                guard let request, request.action == .studyFocus, request.id != handledNavigationID else { return }
                handledNavigationID = request.id
                showingSettings = false
                section = .timer
                if let taskID = request.studyTaskID,
                   tasks.contains(where: { $0.id == taskID && !$0.isCompleted }) {
                    selectedTaskID = taskID
                }
            }
            .onReceive(ticker) { _ in
                timer.tick()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    timer.applicationDidBecomeActive()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return layout {
            VStack(alignment: .leading, spacing: 6) {
                Text("训练计划")
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundStyle(ArchiveTheme.ink)

                Text("今日 \(todayTotals.minutes) 分钟 · 连续 \(streak) 天")
                    .font(.caption)
                    .foregroundStyle(ArchiveTheme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                ProgressRing(progress: goalProgress, lineWidth: 5)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(AppFormatters.percent(goalProgress))
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(ArchiveTheme.ink)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("今日学习目标")
                    .accessibilityValue("已完成 \(AppFormatters.percent(goalProgress))，目标 \(timer.preferences.dailyGoalMinutes) 分钟")

                Button {
                    Haptics.tap()
                    showingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ArchiveTheme.ink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(ArchiveTheme.paperRaised))
                        .overlay(Circle().strokeBorder(ArchiveTheme.ink, lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("番茄钟设置")
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .timer:
            StudyFocusView(
                timer: timer,
                tasks: tasks,
                selectedTaskID: $selectedTaskID,
                todayMinutes: todayTotals.minutes,
                pomodoroCount: todayTotals.pomodoroCount,
                onAddTask: presentNewTask
            )

        case .tasks:
            StudyTasksView(
                tasks: tasks,
                dailyGoalMinutes: timer.preferences.dailyGoalMinutes,
                todayMinutes: todayTotals.minutes,
                streak: streak,
                onAdd: presentNewTask,
                onEdit: { task in
                    editingTask = task
                    showingTaskEditor = true
                },
                onToggle: toggleTask,
                onDelete: deleteTask,
                onFocus: focusTask,
                onEditGoal: { showingSettings = true }
            )

        case .stats:
            StudyStatsView(
                sessions: sessions,
                dailyGoalMinutes: timer.preferences.dailyGoalMinutes,
                onEditGoal: { showingSettings = true }
            )
        }
    }

    // MARK: - Actions

    private func presentNewTask() {
        editingTask = nil
        showingTaskEditor = true
    }

    private func initializeSelectedTaskIfNeeded() {
        guard !didInitializeTask else { return }
        didInitializeTask = true
        if selectedTaskID == nil {
            selectedTaskID = StudyPlanning.automaticFocusTask(tasks)?.id
        }
    }

    private func focusTask(_ task: StudyTask) {
        selectedTaskID = task.id
        section = .timer
        Haptics.select()
    }

    private func toggleTask(_ task: StudyTask) {
        let wasCompleted = task.isCompleted
        let previousCompletedAt = task.completedAt
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? .now : nil
        do {
            try context.save()
            if task.isCompleted && selectedTaskID == task.id { selectedTaskID = nil }
            Haptics.select()
        } catch {
            task.isCompleted = wasCompleted
            task.completedAt = previousCompletedAt
            mutationError = "完成状态没有保存，请重试。你的任务仍然保留。"
        }
    }

    private func deleteTask(_ task: StudyTask) {
        let taskID = task.id
        context.delete(task)
        do {
            try context.save()
            if selectedTaskID == taskID { selectedTaskID = nil }
            Haptics.success()
        } catch {
            context.rollback()
            mutationError = "任务没有删除，请重试。已记录的专注时长不会受影响。"
        }
    }
}
