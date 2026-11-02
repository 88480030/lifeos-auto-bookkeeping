import SwiftUI

private enum StudyTaskFilter: String, CaseIterable, Identifiable {
    case pending = "待完成"
    case today = "今天"
    case completed = "已完成"

    var id: String { rawValue }
}

struct StudyTasksView: View {
    let tasks: [StudyTask]
    let dailyGoalMinutes: Int
    let todayMinutes: Int
    let streak: Int
    let onAdd: () -> Void
    let onEdit: (StudyTask) -> Void
    let onToggle: (StudyTask) -> Void
    let onDelete: (StudyTask) -> Void
    let onFocus: (StudyTask) -> Void
    let onEditGoal: () -> Void

    @State private var searchText = ""
    @State private var filter: StudyTaskFilter = .pending
    @State private var taskToDelete: StudyTask?
    @FocusState private var searchFocused: Bool

    private var unfinishedTasks: [StudyTask] {
        tasks.filter { !$0.isCompleted }.sorted {
            let lhs = $0.plannedDate ?? .distantFuture
            let rhs = $1.plannedDate ?? .distantFuture
            if lhs == rhs {
                if $0.plannedStartMinute != $1.plannedStartMinute { return ($0.plannedStartMinute ?? 1440) < ($1.plannedStartMinute ?? 1440) }
                return $0.createdAt > $1.createdAt
            }
            return lhs < rhs
        }
    }

    private var todayTasks: [StudyTask] {
        unfinishedTasks.filter { task in
            task.plannedDate.map { Calendar.current.isDateInToday($0) } ?? false
        }
    }

    private var completedTasks: [StudyTask] {
        tasks.filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    private var visibleTasks: [StudyTask] {
        let source: [StudyTask]
        switch filter {
        case .pending: source = unfinishedTasks
        case .today: source = todayTasks
        case .completed: source = completedTasks
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }
        return source.filter { $0.title.localizedStandardContains(query) || $0.subject.localizedStandardContains(query) }
    }

    private var goalProgress: Double {
        StudyAnalytics.goalProgress(focusedSeconds: todayMinutes * 60, dailyGoalMinutes: dailyGoalMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            goalCard
            taskSection
        }
        .confirmationDialog("删除学习任务？", isPresented: Binding(
            get: { taskToDelete != nil },
            set: { if !$0 { taskToDelete = nil } }
        ), titleVisibility: .visible) {
            if let task = taskToDelete {
                Button("删除“\(task.title)”", role: .destructive) {
                    onDelete(task)
                    taskToDelete = nil
                }
            }
            Button("取消", role: .cancel) { taskToDelete = nil }
        } message: {
            Text("删除后无法恢复，已记录的专注时长会保留。")
        }
    }

    private var goalCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("今日学习目标")
                        .font(.headline)
                        .foregroundStyle(ArchiveTheme.ink)
                    Spacer()
                    Button("调整", action: onEditGoal)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ArchiveTheme.ink)
                        .frame(minWidth: 44, minHeight: 44)
                        .buttonStyle(.plain)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(todayMinutes)")
                        .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(ArchiveTheme.ink)
                    Text("/ \(dailyGoalMinutes) 分钟")
                        .font(.subheadline)
                        .foregroundStyle(ArchiveTheme.inkSoft)
                    Spacer()
                    if goalProgress >= 1 {
                        Label("已达标", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ArchiveTheme.mintDeep)
                    }
                }
                ProgressBar(progress: goalProgress, tint: ArchiveTheme.mintDeep)
                    .accessibilityLabel("今日学习目标")
                    .accessibilityValue("已学习 \(todayMinutes) 分钟，目标 \(dailyGoalMinutes) 分钟")
                Text(streak > 0 ? "已连续学习 \(streak) 天，保持自己的节奏。" : "完成一次专注，开始积累今天的学习记录。")
                    .font(.caption)
                    .foregroundStyle(ArchiveTheme.inkSoft)
            }
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("学习任务")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(ArchiveTheme.ink)
                Spacer()
                Button {
                    searchFocused = false
                    Haptics.tap()
                    onAdd()
                } label: {
                    Label("新任务", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ArchiveTheme.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(ArchiveTheme.mintWash))
                        .overlay(Capsule().strokeBorder(ArchiveTheme.ink.opacity(0.7), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ArchiveTheme.inkSoft)
                    .accessibilityHidden(true)
                TextField("搜索任务或科目", text: $searchText)
                    .font(.subheadline)
                    .foregroundStyle(ArchiveTheme.ink)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { searchFocused = false }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(ArchiveTheme.inkSoft)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除任务搜索")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, searchText.isEmpty ? 14 : 0)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(ArchiveTheme.paperRaised))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ArchiveTheme.rule, lineWidth: 1))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { filterButtons }
                VStack(alignment: .leading, spacing: 6) { filterButtons }
            }

            if visibleTasks.isEmpty {
                emptyState
            } else {
                Text(searchText.isEmpty ? "\(visibleTasks.count) 个任务 · 点击名称编辑，勾选完成" : "找到 \(visibleTasks.count) 个任务")
                    .font(.caption)
                    .foregroundStyle(ArchiveTheme.inkSoft)
                SurfaceCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleTasks.enumerated()), id: \.element.id) { index, task in
                            StudyTaskRow(
                                task: task,
                                onToggle: { onToggle(task) },
                                onEdit: { onEdit(task) },
                                onDelete: { taskToDelete = task },
                                onFocus: { searchFocused = false; onFocus(task) }
                            )
                            if index < visibleTasks.count - 1 {
                                Rectangle()
                                    .fill(ArchiveTheme.rule)
                                    .frame(height: 1)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    private var filterButtons: some View {
        ForEach(StudyTaskFilter.allCases) { item in
            Button {
                Haptics.select()
                filter = item
            } label: {
                Text("\(item.rawValue) \(count(for: item))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ArchiveTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(filter == item ? ArchiveTheme.mintWash : ArchiveTheme.paperTint))
                    .overlay(Capsule().strokeBorder(filter == item ? ArchiveTheme.ink : ArchiveTheme.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(filter == item ? .isSelected : [])
        }
    }

    private func count(for filter: StudyTaskFilter) -> Int {
        switch filter {
        case .pending: unfinishedTasks.count
        case .today: todayTasks.count
        case .completed: completedTasks.count
        }
    }

    private var emptyState: some View {
        SurfaceCard {
            VStack(spacing: 14) {
                Image(systemName: searchText.isEmpty ? (filter == .completed ? "checkmark.seal" : "books.vertical") : "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(ArchiveTheme.mintDeep)
                    .accessibilityHidden(true)
                Text(emptyTitle)
                    .font(.headline)
                    .foregroundStyle(ArchiveTheme.ink)
                Text(emptyMessage)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ArchiveTheme.inkSoft)
                if !searchText.isEmpty {
                    Button("清除搜索") { searchText = "" }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ArchiveTheme.ink)
                        .frame(minHeight: 44)
                } else if filter != .completed {
                    Button("新建学习任务", action: onAdd)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ArchiveTheme.ink)
                        .frame(minHeight: 44)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
    }

    private var emptyTitle: String {
        if !searchText.isEmpty { return "没有匹配的学习任务" }
        switch filter {
        case .pending: return tasks.isEmpty ? "把想学的事写下来" : "待办任务全部完成了"
        case .today: return "今天还没有安排任务"
        case .completed: return "完成的任务会归档在这里"
        }
    }

    private var emptyMessage: String {
        if !searchText.isEmpty { return "试试其他名称或科目，也可以切换任务状态继续查找。" }
        switch filter {
        case .pending: return "从一个小任务开始；点任务旁的“专注”，就能带着目标进入番茄钟。"
        case .today: return "新建任务并把计划日期设为今天，或前往“待完成”挑选一个任务。"
        case .completed: return "任务完成后点左侧圆圈。你可以随时取消完成，继续学习。"
        }
    }
}
