import SwiftUI

// MARK: - Mode

enum ScheduleMode: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        }
    }
}

struct ScheduleSegmentedControl: View {
    @Binding var selection: ScheduleMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ScheduleMode.allCases) { mode in
                Button {
                    guard selection != mode else { return }
                    Haptics.select()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        selection = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == mode ? ArchiveTheme.ink : ArchiveTheme.inkSoft)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background {
                            if selection == mode {
                                Capsule(style: .continuous)
                                    .fill(ArchiveTheme.mintWash)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(ArchiveTheme.ink.opacity(0.8), lineWidth: 1.1)
                                    )
                                    .matchedGeometryEffect(id: "scheduleMode", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("按\(mode.title)查看日程")
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule(style: .continuous).fill(ArchiveTheme.paperRaised))
        .overlay(Capsule(style: .continuous).strokeBorder(ArchiveTheme.ink.opacity(0.7), lineWidth: 1.4))
    }
}

// MARK: - Task row

struct ScheduleTaskRow: View {
    let task: ScheduleTask
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Haptics.select()
                onToggle()
            } label: {
                CompletionToggleMark(isCompleted: task.isCompleted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "将\(task.title)标为未完成" : "完成\(task.title)")

            Button {
                Haptics.tap()
                onEdit()
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? AppTheme.textSecondary : AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.18), value: task.isCompleted)

                    Text("\(SchedulePlanningHelper.timeRange(task)) · \(AppFormatters.duration(minutes: task.durationMinutes))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        Text("\(task.priority.displayName)优先级 · \(SchedulePlanningHelper.status(task, at: timeline.date))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(!task.isCompleted && task.endAt < timeline.date ? AppTheme.textPrimary : AppTheme.textSecondary)
                    }

                    if let reminder = task.reminderMinutesBefore {
                        Label("提前 \(reminder) 分钟提醒", systemImage: "bell")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("编辑日程")

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textTertiary.opacity(0.6))
                .padding(.top, 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background {
            ArchiveTheme.mintWash
                .opacity(task.isCompleted ? 0.65 : 0)
                .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.20), value: task.isCompleted)
        }
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
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Timeline

struct ScheduleTimelineList: View {
    let tasks: [ScheduleTask]
    var isFiltering = false
    var onResetFilters: () -> Void = {}
    let onEdit: (ScheduleTask) -> Void
    let onToggle: (ScheduleTask) -> Void
    let onDelete: (ScheduleTask) -> Void
    let onAdd: () -> Void

    var body: some View {
        SurfaceCard(padding: 0) {
            if tasks.isEmpty {
                VStack(spacing: 12) {
                    EmptyStateView(
                        icon: isFiltering ? "magnifyingglass" : "calendar.badge.plus",
                        title: isFiltering ? "当天没有匹配的生活日程" : "这一天还没有生活日程",
                        message: isFiltering ? "试试其他关键词或清除筛选，也可以切换日期查看。" : "把看医生、聚会、出行、办事安排在这里，和学习计划分开。"
                    )
                    Button {
                        Haptics.tap()
                        if isFiltering { onResetFilters() } else { onAdd() }
                    } label: {
                        Text(isFiltering ? "清除搜索与筛选" : "添加生活日程")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ArchiveTheme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(ArchiveTheme.mintWash)
                            )
                    }
                    .buttonStyle(PressableScaleStyle())
                    .padding(.horizontal, 18)
                }
                .padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        ScheduleTaskRow(
                            task: task,
                            onEdit: { onEdit(task) },
                            onToggle: { onToggle(task) },
                            onDelete: { onDelete(task) }
                        )
                        if index < tasks.count - 1 {
                            Rectangle()
                                .fill(AppTheme.separator.opacity(0.55))
                                .frame(height: 0.7)
                                .padding(.leading, 48)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Next task

struct ScheduleNextTaskCard: View {
    let task: ScheduleTask
    let onEdit: (ScheduleTask) -> Void

    var body: some View {
        SurfaceCard(padding: 16) {
            Button { onEdit(task) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        Label(SchedulePlanningHelper.focusTitle(task, at: timeline.date), systemImage: "clock")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Text(task.title)
                        .font(.lifeCard)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(AppFormatters.shortDate(task.startAt)) · \(SchedulePlanningHelper.timeRange(task))")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("编辑日程")
        }
    }
}

// MARK: - Search and planning

enum ScheduleStatusFilter: String, CaseIterable, Identifiable {
    case all, pending, completed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .pending: "未完成"
        case .completed: "已完成"
        }
    }

    func includes(_ task: ScheduleTask) -> Bool {
        switch self {
        case .all: true
        case .pending: !task.isCompleted
        case .completed: task.isCompleted
        }
    }
}

enum SchedulePlanningHelper {
    static func matches(_ task: ScheduleTask, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || task.title.localizedStandardContains(query) || task.notes.localizedStandardContains(query)
    }

    static func status(_ task: ScheduleTask, at now: Date) -> String {
        if task.isCompleted { return "已完成" }
        if task.endAt <= now { return "已过计划时间" }
        if task.startAt <= now { return "正在进行" }
        return "待开始"
    }

    static func focusTitle(_ task: ScheduleTask, at now: Date) -> String {
        if task.endAt <= now { return "待处理 · 已过计划时间" }
        if task.startAt <= now { return "正在进行" }
        return "接下来"
    }

    @MainActor
    static func timeRange(_ task: ScheduleTask, calendar: Calendar = .current) -> String {
        let end = calendar.isDate(task.startAt, inSameDayAs: task.endAt)
            ? AppFormatters.time(task.endAt)
            : "\(AppFormatters.shortDate(task.endAt)) \(AppFormatters.time(task.endAt))"
        return "\(AppFormatters.time(task.startAt)) – \(end)"
    }

    static func nextTask(_ tasks: [ScheduleTask], at now: Date = .now) -> ScheduleTask? {
        let pending = tasks.filter { !$0.isCompleted }.sorted { $0.startAt < $1.startAt }
        return pending.first { $0.startAt <= now && $0.endAt > now }
            ?? pending.first { $0.startAt > now }
            ?? pending.first
    }

    static func overlapCount(_ tasks: [ScheduleTask]) -> Int {
        let pending = tasks.filter { !$0.isCompleted && $0.durationMinutes > 0 }.sorted { $0.startAt < $1.startAt }
        var count = 0
        for (index, task) in pending.enumerated() {
            for other in pending.dropFirst(index + 1) {
                guard other.startAt < task.endAt else { break }
                if task.startAt < other.endAt { count += 1 }
            }
        }
        return count
    }
}

// MARK: - Helpers

enum ScheduleCalendarHelper {
    static func startOfWeek(_ date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let mondayOffset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -mondayOffset, to: start) ?? start
    }

    static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func weekDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let start = startOfWeek(date, calendar: calendar)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func monthSlots(containing date: Date, calendar: Calendar = .current) -> [Date?] {
        let monthStart = startOfMonth(date, calendar: calendar)
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let weekday = calendar.component(.weekday, from: monthStart)
        let mondayOffset = (weekday + 5) % 7
        var slots: [Date?] = Array(repeating: nil, count: mondayOffset)
        for offset in 0..<dayCount {
            slots.append(calendar.date(byAdding: .day, value: offset, to: monthStart))
        }
        return slots
    }

    static func taskCountsByDay(_ tasks: [ScheduleTask], calendar: Calendar = .current) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for task in tasks {
            let day = calendar.startOfDay(for: task.startAt)
            counts[day, default: 0] += 1
        }
        return counts
    }
}
