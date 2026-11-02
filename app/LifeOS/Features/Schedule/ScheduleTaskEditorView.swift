import SwiftUI
import SwiftData

struct ScheduleTaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ScaledMetric(relativeTo: .subheadline) private var priorityMinimumWidth: CGFloat = 110

    let task: ScheduleTask?
    private let initialDraft: ScheduleTaskDraft

    @State private var title: String
    @State private var notes: String
    @State private var startAt: Date
    @State private var durationMinutes: Int
    @State private var priority: TaskPriority
    @State private var reminderMinutes: Int
    @State private var repeatRule: RepeatRule
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteSeriesConfirmation = false
    @State private var showingDiscardConfirmation = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case title, notes }

    init(task: ScheduleTask?, defaultStart: Date) {
        self.task = task
        let draft = ScheduleTaskDraft(
            title: task?.title ?? "", notes: task?.notes ?? "",
            startAt: task?.startAt ?? defaultStart,
            durationMinutes: max(15, task?.durationMinutes ?? 30),
            priority: task?.priority ?? .normal,
            reminderMinutes: 15,
            repeatRule: RepeatRule.from(task?.repeatRuleRaw)
        )
        initialDraft = draft
        _title = State(initialValue: draft.title)
        _notes = State(initialValue: draft.notes)
        _startAt = State(initialValue: draft.startAt)
        _durationMinutes = State(initialValue: draft.durationMinutes)
        _priority = State(initialValue: draft.priority)
        _reminderMinutes = State(initialValue: draft.reminderMinutes)
        _repeatRule = State(initialValue: draft.repeatRule)
    }

    private var endAt: Date {
        startAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    private var draft: ScheduleTaskDraft {
        ScheduleTaskDraft(
            title: title, notes: notes, startAt: startAt,
            durationMinutes: durationMinutes, priority: priority,
            reminderMinutes: reminderMinutes, repeatRule: repeatRule
        )
    }

    private var hasUnsavedChanges: Bool { draft != initialDraft }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var occurrenceCount: Int {
        switch repeatRule {
        case .daily, .weekdays: 30
        case .weekly: 16
        case .monthly: 12
        case .none: 1
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("事项名称")
                            TextField("例如：看医生、朋友聚会、取快递", text: $title, axis: .vertical)
                                .font(.body.weight(.medium))
                                .foregroundStyle(AppTheme.textPrimary)
                                .frame(minHeight: 44)
                                .focused($focusedField, equals: .title)
                                .accessibilityLabel("生活日程名称，必填")
                            Text("用于学习之外的安排；学习任务在「学习」中管理。")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    timeCard
                    priorityCard
                    reminderCard
                    repeatCard
                    notesCard

                    if task != nil { deleteSection }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            Button { save() } label: {
                Text(task == nil ? "创建生活日程" : "保存修改")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ArchiveTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(ArchiveTheme.mintWash))
                    .overlay(Capsule().strokeBorder(ArchiveTheme.ink, lineWidth: 1.5))
            }
            .buttonStyle(PressableScaleStyle())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)
            .accessibilityHint(canSave ? "保存日程和提醒设置" : "请先填写日程名称")
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background { AppBackground() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(hasUnsavedChanges)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
            }
        }
        .alert("删除这个日程？", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteTask() }
        } message: {
            Text("只删除这一次安排。")
        }
        .alert("删除整个重复系列？", isPresented: $showingDeleteSeriesConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除整个系列", role: .destructive) { deleteSeries() }
        } message: {
            Text("该系列的所有日程都会被删除。")
        }
        .confirmationDialog("放弃未保存的修改？", isPresented: $showingDiscardConfirmation, titleVisibility: .visible) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃修改", role: .destructive) { dismiss() }
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

    private var header: some View {
        HStack(spacing: 12) {
            Text(task == nil ? "新建生活日程" : "编辑生活日程")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer(minLength: 4)
            Button {
                if hasUnsavedChanges { showingDiscardConfirmation = true } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppTheme.surface))
                    .overlay(Circle().strokeBorder(AppTheme.separator, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭日程编辑")
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.headline).foregroundStyle(AppTheme.textPrimary)
    }

    private var timeCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("时间安排")
                Text("结束于 \(AppFormatters.shortDate(endAt)) \(AppFormatters.time(endAt))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("开始时间")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                    DatePicker("开始时间", selection: $startAt)
                        .labelsHidden()
                        .tint(AppTheme.accent)
                        .frame(minHeight: 44)
                        .accessibilityLabel("日程开始日期和时间")
                }

                Stepper(value: $durationMinutes, in: 15...max(240, initialDraft.durationMinutes), step: 15) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("持续时间").font(.subheadline)
                        Text(AppFormatters.duration(minutes: durationMinutes))
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(AppTheme.textPrimary)
                }
                .accessibilityValue(AppFormatters.duration(minutes: durationMinutes))
            }
        }
    }

    private var priorityCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("优先级")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: priorityMinimumWidth), spacing: 8)], spacing: 8) {
                    ForEach([TaskPriority.low, .normal, .high, .urgent], id: \.self) { item in
                        Button {
                            Haptics.select()
                            priority = item
                        } label: {
                            HStack(spacing: 6) {
                                if priority == item { Image(systemName: "checkmark") }
                                Text(item.displayName)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(priority == item ? AppTheme.accentSoft : AppTheme.background))
                            .overlay(Capsule().strokeBorder(priority == item ? AppTheme.accent : AppTheme.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(priority == item ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var reminderCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("提醒")
                Label("提前 15 分钟提醒", systemImage: "bell.badge")
                    .font(.body)
                    .frame(minHeight: 44)
                Text("提醒需在系统设置中允许通知；过去的提醒时间不会补发。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var repeatCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("重复安排")
                if task != nil {
                    Text(repeatRule.displayName)
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("本次编辑只修改这一次安排。需要新的重复计划时，请新建日程。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    Picker("重复频率", selection: $repeatRule) {
                        ForEach(RepeatRule.allCases, id: \.self) { rule in
                            Text(rule.displayName).tag(rule)
                        }
                    }
                    .tint(AppTheme.accent)
                    .frame(minHeight: 44)

                    if repeatRule != .none {
                        let dates = repeatRule.occurrences(startingAt: startAt, count: occurrenceCount)
                        if let first = dates.first, let last = dates.last {
                            Text("将创建 \(dates.count) 次安排：\(AppFormatters.shortDate(first)) 至 \(AppFormatters.shortDate(last))。")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if repeatRule == .weekdays {
                            Text("工作日按周一至周五安排，不自动识别法定节假日或调休。")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var notesCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("备注")
                TextEditor(text: $notes)
                    .font(.body)
                    .foregroundStyle(AppTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100)
                    .focused($focusedField, equals: .notes)
                    .accessibilityLabel("日程备注，选填")
            }
        }
    }

    private var deleteSection: some View {
        VStack(spacing: 8) {
            Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                Label("删除这个日程", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.coral)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(AppTheme.coral.opacity(0.08)))
            }
            .buttonStyle(.plain)

            if task?.seriesID != nil {
                Button("删除整个重复系列", role: .destructive) { showingDeleteSeriesConfirmation = true }
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.coral)
                    .frame(minHeight: 44)
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        focusedField = nil

        if let task {
            task.title = trimmedTitle
            task.notes = notes
            task.startAt = startAt
            task.durationMinutes = max(15, durationMinutes)
            task.priority = priority
            task.reminderMinutesBefore = reminderMinutes > 0 ? reminderMinutes : nil
        } else {
            let dates = repeatRule.occurrences(startingAt: startAt, count: occurrenceCount)
            let seriesID = repeatRule == .none ? nil : UUID().uuidString
            for date in dates {
                context.insert(ScheduleTask(
                    title: trimmedTitle, startAt: date, durationMinutes: durationMinutes,
                    priority: priority, notes: notes,
                    reminderMinutesBefore: reminderMinutes > 0 ? reminderMinutes : nil,
                    repeatRuleRaw: repeatRule == .none ? nil : repeatRule.rawValue,
                    seriesID: seriesID
                ))
            }
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            errorMessage = "日程未能保存。填写的内容仍保留，请重试。"
            return
        }
        Haptics.success()
        Task {
            if reminderMinutes > 0 {
                _ = await ScheduleNotificationManager.requestPermissionIfNeeded()
            }
            await ScheduleNotificationManager.rescheduleAll(context: context)
        }
        dismiss()
    }

    private func deleteTask() {
        guard let task else { return }
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
        dismiss()
    }

    private func deleteSeries() {
        guard let task, let seriesID = task.seriesID else { return }
        do {
            let all = try context.fetch(FetchDescriptor<ScheduleTask>())
            let series = all.filter { $0.seriesID == seriesID }
            let ids = series.map(\.id)
            for item in series { context.delete(item) }
            try context.save()
            ids.forEach { ScheduleNotificationManager.cancel(taskID: $0) }
        } catch {
            context.rollback()
            errorMessage = "重复系列未能删除，请重试。"
            return
        }
        Task { await ScheduleNotificationManager.rescheduleAll(context: context) }
        Haptics.success()
        dismiss()
    }
}

private struct ScheduleTaskDraft: Equatable {
    let title: String
    let notes: String
    let startAt: Date
    let durationMinutes: Int
    let priority: TaskPriority
    let reminderMinutes: Int
    let repeatRule: RepeatRule
}
