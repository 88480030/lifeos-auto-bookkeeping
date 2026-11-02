import SwiftUI
import SwiftData

struct StudyTaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let task: StudyTask?

    @State private var title: String
    @State private var subject: String
    @State private var estimatedMinutes: Int
    @State private var hasPlannedDate: Bool
    @State private var hasPlannedTime: Bool
    @State private var plannedTime: Date
    @State private var plannedDate: Date
    @State private var showingDeleteConfirmation = false
    @State private var saveError: String?

    init(task: StudyTask?) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _subject = State(initialValue: task?.subject ?? "")
        _estimatedMinutes = State(initialValue: task?.estimatedMinutes ?? 25)
        _hasPlannedDate = State(initialValue: task?.plannedDate != nil)
        _plannedDate = State(initialValue: task?.plannedDate ?? .now)
        _hasPlannedTime = State(initialValue: task?.plannedStartMinute != nil)
        _plannedTime = State(initialValue: Calendar.current.date(bySettingHour: (task?.plannedStartMinute ?? 540) / 60, minute: (task?.plannedStartMinute ?? 540) % 60, second: 0, of: .now) ?? .now)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("任务名称").font(.headline).foregroundStyle(ArchiveTheme.ink)
                            TextField("学习任务名称，例如：背 50 个单词", text: $title)
                                .font(.body)
                                .foregroundStyle(AppTheme.textPrimary)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .frame(minHeight: 44)
                                .accessibilityLabel("任务名称")
                        }
                    }

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("科目").font(.headline).foregroundStyle(ArchiveTheme.ink)
                                Spacer()
                                Text("可选")
                                    .font(.caption)
                                    .foregroundStyle(ArchiveTheme.inkSoft)
                            }
                            TextField("例如：英语、数学、阅读", text: $subject)
                                .font(.body)
                                .foregroundStyle(AppTheme.textPrimary)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .frame(minHeight: 44)
                                .accessibilityLabel("科目，可选")
                        }
                    }

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("预计用时").font(.headline).foregroundStyle(ArchiveTheme.ink)
                                Spacer()
                                Text("\(estimatedMinutes) 分钟")
                                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(AppTheme.gold)
                            }
                            Stepper("预计学习时长", value: $estimatedMinutes, in: 5...180, step: 5)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(isOn: $hasPlannedDate) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("计划日期").font(.headline).foregroundStyle(ArchiveTheme.ink)
                                    Text("设置计划日期")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppTheme.textPrimary)
                                }
                            }
                            .tint(AppTheme.gold)

                            if hasPlannedDate {
                                Toggle("安排具体时间", isOn: $hasPlannedTime).tint(AppTheme.gold)
                                if hasPlannedTime {
                                    DatePicker("开始时间", selection: $plannedTime, displayedComponents: .hourAndMinute)
                                    Text("结束时间：" + AppFormatters.time(plannedTime.addingTimeInterval(Double(estimatedMinutes * 60))))
                                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                                }
                                DatePicker("计划日期", selection: $plannedDate, displayedComponents: .date)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .tint(AppTheme.gold)
                            }
                        }
                    }

                    if task != nil {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("删除这个学习任务", systemImage: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.coral)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Capsule(style: .continuous).fill(AppTheme.coral.opacity(0.08)))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(AppTheme.coral.opacity(0.25), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(PressableScaleStyle())
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            Button {
                save()
            } label: {
                Text(task == nil ? "创建学习任务" : "保存修改")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ArchiveTheme.stripInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Capsule(style: .continuous)
                            .fill(ArchiveTheme.strip)
                    )
            }
            .buttonStyle(PressableScaleStyle())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background { AppBackground() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("删除学习任务？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteTask() }
        } message: {
            Text("删除后无法恢复，已记录的专注时长会保留。")
        }
        .alert("学习任务未保存", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("知道了", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "请稍后重试。")
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppTheme.surface.opacity(0.7)))
                    .overlay(Circle().strokeBorder(AppTheme.separator.opacity(0.7), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭学习任务编辑")

            Spacer()

            Text(task == nil ? "新建学习任务" : "编辑学习任务")
                .font(.system(.headline, design: .serif).weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var selectedStartMinute: Int? {
        guard hasPlannedDate && hasPlannedTime else { return nil }
        return Calendar.current.component(.hour, from: plannedTime) * 60 + Calendar.current.component(.minute, from: plannedTime)
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let previous = task.map { ($0.title, $0.subject, $0.estimatedMinutes, $0.plannedDate, $0.plannedStartMinute) }
        let savedTask: StudyTask
        if let task {
            savedTask = task
            task.title = trimmedTitle
            task.subject = trimmedSubject
            task.estimatedMinutes = max(5, estimatedMinutes)
            task.plannedDate = hasPlannedDate ? plannedDate : nil
            task.plannedStartMinute = selectedStartMinute
        } else {
            savedTask = StudyTask(
                title: trimmedTitle,
                subject: trimmedSubject,
                estimatedMinutes: max(5, estimatedMinutes),
                plannedDate: hasPlannedDate ? plannedDate : nil,
                plannedStartMinute: selectedStartMinute
            )
            context.insert(savedTask)
        }

        do {
            try context.save()
            Haptics.success()
            dismiss()
        } catch {
            if let previous {
                savedTask.title = previous.0
                savedTask.subject = previous.1
                savedTask.estimatedMinutes = previous.2
                savedTask.plannedDate = previous.3
                savedTask.plannedStartMinute = previous.4
            } else {
                context.delete(savedTask)
            }
            saveError = "保存失败，请稍后重试。你填写的内容仍然保留在此页面。"
        }
    }

    private func deleteTask() {
        guard let task else { return }
        context.delete(task)
        do {
            try context.save()
            Haptics.success()
            dismiss()
        } catch {
            context.rollback()
            saveError = "任务没有删除，请稍后重试。"
        }
    }
}
