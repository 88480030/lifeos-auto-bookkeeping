import SwiftData
import SwiftUI

/// A Reminders-style agenda within the brief's single continuous surface.
struct BriefRemindersView: View {
    let scheduleTasks: [ScheduleTask]
    let studyTasks: [StudyTask]
    let now: Date
    let onShowSummary: (BriefTopic) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var scope = ReminderAgendaSnapshot.Scope.today
    @State private var includesCompleted = false
    @State private var creatingStudy = false
    @State private var editingStudy: StudyTask?
    @State private var editingSchedule: ScheduleTask?
    @State private var saveError: String?
    @State private var lastCompleted: ReminderAgendaSnapshot.Entry?

    private var agenda: ReminderAgendaSnapshot {
        ReminderAgendaSnapshot(scheduleTasks: scheduleTasks, studyTasks: studyTasks,
                               now: now, includesCompleted: includesCompleted, scope: scope)
    }

    var body: some View {
        let snapshot = agenda
        let firstUpcomingDate = snapshot.sections.compactMap(\.date).first {
            $0 > Calendar.current.startOfDay(for: now)
        }
        VStack(alignment: .leading, spacing: 20) {
            smartLists(snapshot)
            MangaPanel(fill: ArchiveTheme.paperRaised, borderWidth: 1, hardShadow: false) {
                reminderList(snapshot, firstUpcomingDate: firstUpcomingDate)
            }
        }
        .sheet(isPresented: $creatingStudy) { StudyTaskEditorView(task: nil) }
        .sheet(item: $editingStudy) { task in
            StudyTaskEditorView(task: task).id(task.id)
        }
        .sheet(item: $editingSchedule) { task in
            ScheduleTaskEditorView(task: task, defaultStart: task.startAt).id(task.id)
        }
        .alert("未能保存", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("好", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "请重试。") }
        .accessibilityIdentifier("brief.reminders")
    }

    private func reminderList(_ snapshot: ReminderAgendaSnapshot, firstUpcomingDate: Date?) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(scope == .today ? "今天" : "计划").font(.title2.weight(.bold))
                Spacer(minLength: 8)
                Menu {
                    Toggle("显示已完成（\(snapshot.completedCount)）", isOn: $includesCompleted)
                    Divider()
                    Button("收支摘要", systemImage: "creditcard") { onShowSummary(.finance) }
                    Button("学习摘要", systemImage: "book.closed") { onShowSummary(.study) }
                } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("提醒事项显示选项")
            }
            .padding(.bottom, 8)

            ForEach(snapshot.sections) { section in
                BriefReminderSection(section: section, now: now,
                    initiallyExpanded: section.date.map {
                        Calendar.current.isDate($0, inSameDayAs: now) || $0 == firstUpcomingDate
                    } ?? false, onToggle: toggle, onEdit: edit)
            }

            if let entry = lastCompleted, entry.isCompleted {
                Button {
                    toggle(entry)
                    lastCompleted = nil
                } label: {
                    Label("已完成，撤销", systemImage: "arrow.uturn.backward")
                        .font(.subheadline)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("撤销完成\(entry.title)")
            }

            Menu {
                Button("新建日程", systemImage: "calendar.badge.plus") {
                    AppNavigationCenter.shared.open(.newSchedule)
                }
                Button("新建学习任务", systemImage: "book.badge.plus") {
                    creatingStudy = true
                }
            } label: {
                Label("新增提醒事项", systemImage: "plus.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ArchiveTheme.mintDeep)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }
            .padding(.top, 8)
            .accessibilityIdentifier("brief.reminders.add")
        }
    }

    private func smartLists(_ snapshot: ReminderAgendaSnapshot) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            smartTile("今天", count: snapshot.todayPendingCount, candidate: .today)
            smartTile("计划", count: snapshot.scheduledPendingCount, candidate: .scheduled)
        }
        .accessibilityIdentifier("brief.reminders.smartLists")
    }

    private func smartTile(_ title: String, count: Int, candidate: ReminderAgendaSnapshot.Scope) -> some View {
        let isToday = candidate == .today
        let selected = scope == candidate
        return Button {
            guard !selected else { return }
            Haptics.select()
            scope = candidate
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    if isToday {
                        todayCalendarIcon
                    } else {
                        Image(systemName: "calendar").font(.title2.weight(.semibold))
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 8)
                    Text(count, format: .number)
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(title).font(.title3.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .background(
                LinearGradient(colors: isToday
                    ? [ArchiveTheme.reminderToday, ArchiveTheme.reminderTodayEnd]
                    : [ArchiveTheme.reminderScheduled, ArchiveTheme.reminderScheduledEnd],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? ArchiveTheme.reminderSelection : .clear, lineWidth: 3.5)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selected)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue("\(count) 项未完成")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(isToday ? "brief.reminders.today" : "brief.reminders.scheduled")
    }

    private var todayCalendarIcon: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3).strokeBorder(.white, lineWidth: 1.8)
            Rectangle().fill(.white).frame(height: 4).padding(.horizontal, 1).padding(.top, 1)
            Text("\(Calendar.current.component(.day, from: now))")
                .font(.caption2.weight(.bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 4)
        }
        .frame(width: 25, height: 26)
        .accessibilityHidden(true)
    }

    private func edit(_ entry: ReminderAgendaSnapshot.Entry) {
        switch entry {
        case .study(let task): editingStudy = task
        case .schedule(let task): editingSchedule = task
        }
    }

    private func toggle(_ entry: ReminderAgendaSnapshot.Entry) {
        let wasCompleted = entry.isCompleted
        var previousCompletedAt: Date?
        switch entry {
        case .study(let task):
            previousCompletedAt = task.completedAt
            task.isCompleted.toggle()
            task.completedAt = task.isCompleted ? .now : nil
        case .schedule(let task): task.isCompleted.toggle()
        }
        do {
            try context.save()
            if case .schedule(let task) = entry {
                if task.isCompleted { ScheduleNotificationManager.cancel(taskID: task.id) }
                Task { await ScheduleNotificationManager.rescheduleAll(context: context) }
            }
            lastCompleted = entry.isCompleted ? entry : nil
            Haptics.select()
        } catch {
            switch entry {
            case .study(let task): task.isCompleted = wasCompleted; task.completedAt = previousCompletedAt
            case .schedule(let task): task.isCompleted = wasCompleted
            }
            saveError = "完成状态没有保存，请重试。任务仍然保留。"
        }
    }
}

private struct BriefReminderSection: View {
    let section: ReminderAgendaSnapshot.Section
    let now: Date
    let onToggle: (ReminderAgendaSnapshot.Entry) -> Void
    let onEdit: (ReminderAgendaSnapshot.Entry) -> Void
    @State private var isExpanded: Bool

    init(section: ReminderAgendaSnapshot.Section, now: Date, initiallyExpanded: Bool,
         onToggle: @escaping (ReminderAgendaSnapshot.Entry) -> Void,
         onEdit: @escaping (ReminderAgendaSnapshot.Entry) -> Void) {
        self.section = section
        self.now = now
        self.onToggle = onToggle
        self.onEdit = onEdit
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var isOverdue: Bool {
        section.date.map { $0 < Calendar.current.startOfDay(for: now) } ?? false
    }
    private var heading: String {
        guard let date = section.date else { return "未排期" }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "今天" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "明天" }
        return AppFormatters.shortDate(date)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if section.entries.isEmpty {
                Text("今天没有已排期的任务。")
                    .font(.subheadline).foregroundStyle(ArchiveTheme.inkSoft)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(section.entries) { entry in
                    reminderRow(entry)
                    if entry.id != section.entries.last?.id {
                        Divider().overlay(ArchiveTheme.rule).padding(.leading, 44)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(heading).font(.title3.weight(.bold))
                    Spacer(minLength: 8)
                    Text("\(section.entries.count)").font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                if let date = section.date {
                    Text((isOverdue ? "已过期 · " : "") + date.formatted(.dateTime.year().month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                        .font(.caption)
                } else {
                    Text("尚未指定日期，不计入今天")
                        .font(.caption)
                }
            }
            .foregroundStyle(isOverdue ? ArchiveTheme.coral : ArchiveTheme.ink)
            .frame(minHeight: 52)
            .padding(.vertical, 8)
        }
        .tint(ArchiveTheme.inkSoft)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Divider().overlay(ArchiveTheme.rule) }
    }

    private func reminderRow(_ entry: ReminderAgendaSnapshot.Entry) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Button { onToggle(entry) } label: {
                CompletionToggleMark(isCompleted: entry.isCompleted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isCompleted ? "将\(entry.title)标为未完成" : "完成\(entry.title)")
            .accessibilityIdentifier("brief.reminders.toggle.\(entry.id)")

            Button { onEdit(entry) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title)
                        .font(.body)
                        .strikethrough(entry.isCompleted)
                        .foregroundStyle(entry.isCompleted ? ArchiveTheme.inkSoft : ArchiveTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail(entry))
                        .font(.caption)
                        .foregroundStyle(ArchiveTheme.inkSoft)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(entry.title)，\(detail(entry))，编辑任务")
        }
        .accessibilityElement(children: .contain)
    }

    private func detail(_ entry: ReminderAgendaSnapshot.Entry) -> String {
        switch entry {
        case .study(let task):
            let time = task.plannedTimeRange ?? (task.plannedDate == nil ? "未排期" : "时间待定")
            return "\(time) · 学习 · \(AppFormatters.duration(minutes: task.estimatedMinutes))"
        case .schedule(let task):
            return AppFormatters.timeRange(start: task.startAt, end: task.endAt) + " · 日程"
        }
    }
}
