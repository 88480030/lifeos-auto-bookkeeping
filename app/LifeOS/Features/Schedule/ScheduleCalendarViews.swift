import SwiftUI

// MARK: - Day

struct ScheduleDayView: View {
    let date: Date
    let tasks: [ScheduleTask]
    let allTasks: [ScheduleTask]
    let studyCounts: [Date: Int]
    let expensesByDay: [Date: ScheduleExpenseDay]
    let nextTask: ScheduleTask?
    let isFiltering: Bool
    let onResetFilters: () -> Void
    let onEdit: (ScheduleTask) -> Void
    let onToggle: (ScheduleTask) -> Void
    let onDelete: (ScheduleTask) -> Void
    let onAdd: () -> Void
    let onOpenRecords: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if Calendar.current.isDateInToday(date) {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    Label("现在 \(AppFormatters.time(timeline.date))", systemImage: "clock")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            ScheduleExpenseSummaryView(
                date: date,
                summary: expensesByDay[Calendar.current.startOfDay(for: date)],
                onOpenRecords: onOpenRecords
            )

            if let nextTask {
                ScheduleNextTaskCard(task: nextTask, onEdit: onEdit)
            }

            ScheduleAgendaSection(
                date: date, tasks: tasks, allTasks: allTasks,
                isFiltering: isFiltering, onResetFilters: onResetFilters,
                onEdit: onEdit, onToggle: onToggle, onDelete: onDelete, onAdd: onAdd
            )
        }
    }
}

// MARK: - Week

struct ScheduleWeekView: View {
    @Binding var selectedDate: Date
    let tasks: [ScheduleTask]
    let allTasks: [ScheduleTask]
    let studyCounts: [Date: Int]
    let expensesByDay: [Date: ScheduleExpenseDay]
    let isFiltering: Bool
    let onResetFilters: () -> Void
    let onEdit: (ScheduleTask) -> Void
    let onToggle: (ScheduleTask) -> Void
    let onDelete: (ScheduleTask) -> Void
    let onAdd: () -> Void
    let onOpenRecords: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var dayCellWidth: CGFloat = 44
    private let calendar = Calendar.current
    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    private var weekDays: [Date] {
        ScheduleCalendarHelper.weekDays(containing: selectedDate, calendar: calendar)
    }

    private var dayPlans: [Date: ScheduleCalendarDayPlan] {
        ScheduleCalendarDayPlan.grouped(scheduleTasks: allTasks, studyCounts: studyCounts, calendar: calendar)
    }

    var body: some View {
        let plans = dayPlans
        return VStack(alignment: .leading, spacing: 18) {
            SurfaceCard(padding: 8) {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                            dayCell(day, weekdaySymbol: weekdaySymbols[index], plan: plans[calendar.startOfDay(for: day)] ?? ScheduleCalendarDayPlan())
                        }
                    }
                    .frame(minWidth: dayCellWidth * 7)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }

            ScheduleCalendarPlanLegend()
            ScheduleExpenseLegend()
            ScheduleExpenseSummaryView(
                date: selectedDate,
                summary: expensesByDay[calendar.startOfDay(for: selectedDate)],
                onOpenRecords: onOpenRecords
            )

            ScheduleAgendaSection(
                date: selectedDate,
                tasks: ScheduleAnalytics.tasks(tasks, on: selectedDate, calendar: calendar),
                allTasks: ScheduleAnalytics.tasks(allTasks, on: selectedDate, calendar: calendar),
                isFiltering: isFiltering, onResetFilters: onResetFilters,
                onEdit: onEdit, onToggle: onToggle, onDelete: onDelete, onAdd: onAdd
            )
        }
    }

    private func dayCell(_ day: Date, weekdaySymbol: String, plan: ScheduleCalendarDayPlan) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let expenseSummary = expensesByDay[calendar.startOfDay(for: day)]
        let expenseCount = expenseSummary?.transactionCount ?? 0

        return Button {
            Haptics.select()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                selectedDate = calendar.startOfDay(for: day)
            }
        } label: {
            VStack(spacing: 5) {
                Text(weekdaySymbol)
                    .font(.caption)
                ScheduleDateBadge(dayNumber: calendar.component(.day, from: day), summary: expenseSummary)
                ScheduleCalendarPlanMarks(plan: plan)
            }
            .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
            .frame(minWidth: dayCellWidth, minHeight: 96)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? AppTheme.accentSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? AppTheme.accent : (calendar.isDateInToday(day) ? AppTheme.separator : Color.clear), lineWidth: 1)
            )
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel("\(AppFormatters.dateHeader(day))，\(plan.lifeCount)件生活日程，\(plan.studyCount)项\(isFiltering ? "匹配学习计划" : "学习计划")\(expenseCount > 0 ? "，已记支出 \(expenseCount) 笔" : "")\(calendar.isDateInToday(day) ? "，今天" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Month

struct ScheduleMonthView: View {
    @Binding var selectedDate: Date
    let month: Date
    let tasks: [ScheduleTask]
    let allTasks: [ScheduleTask]
    let studyCounts: [Date: Int]
    let expensesByDay: [Date: ScheduleExpenseDay]
    let isFiltering: Bool
    let onResetFilters: () -> Void
    let onEdit: (ScheduleTask) -> Void
    let onToggle: (ScheduleTask) -> Void
    let onDelete: (ScheduleTask) -> Void
    let onAdd: () -> Void
    let onOpenRecords: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var dayCellWidth: CGFloat = 44
    private let calendar = Calendar.current
    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    private var slots: [Date?] {
        ScheduleCalendarHelper.monthSlots(containing: month, calendar: calendar)
    }

    private var dayPlans: [Date: ScheduleCalendarDayPlan] {
        ScheduleCalendarDayPlan.grouped(scheduleTasks: allTasks, studyCounts: studyCounts, calendar: calendar)
    }

    var body: some View {
        let plans = dayPlans
        return VStack(alignment: .leading, spacing: 18) {
            SurfaceCard(padding: 8) {
                ScrollView(.horizontal) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: dayCellWidth), spacing: 0), count: 7), spacing: 5) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(minWidth: dayCellWidth)
                                .padding(.vertical, 4)
                        }

                        ForEach(Array(slots.enumerated()), id: \.offset) { _, day in
                            if let day {
                                monthCell(day, plan: plans[calendar.startOfDay(for: day)] ?? ScheduleCalendarDayPlan())
                            } else {
                                Color.clear.frame(minHeight: 84)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .frame(minWidth: dayCellWidth * 7)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }

            ScheduleCalendarPlanLegend()
            ScheduleExpenseLegend()
            ScheduleExpenseSummaryView(
                date: selectedDate,
                summary: expensesByDay[calendar.startOfDay(for: selectedDate)],
                onOpenRecords: onOpenRecords
            )

            ScheduleAgendaSection(
                date: selectedDate,
                tasks: ScheduleAnalytics.tasks(tasks, on: selectedDate, calendar: calendar),
                allTasks: ScheduleAnalytics.tasks(allTasks, on: selectedDate, calendar: calendar),
                isFiltering: isFiltering, onResetFilters: onResetFilters,
                onEdit: onEdit, onToggle: onToggle, onDelete: onDelete, onAdd: onAdd
            )
        }
    }

    private func monthCell(_ day: Date, plan: ScheduleCalendarDayPlan) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let expenseSummary = expensesByDay[calendar.startOfDay(for: day)]
        let expenseCount = expenseSummary?.transactionCount ?? 0

        return Button {
            Haptics.select()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                selectedDate = calendar.startOfDay(for: day)
            }
        } label: {
            VStack(spacing: 3) {
                ScheduleDateBadge(dayNumber: calendar.component(.day, from: day), summary: expenseSummary)
                ScheduleCalendarPlanMarks(plan: plan)
            }
            .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
            .frame(minWidth: dayCellWidth, minHeight: 84)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? AppTheme.accentSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? AppTheme.accent : (isToday ? AppTheme.separator : Color.clear), lineWidth: 1)
            )
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel("\(AppFormatters.dateHeader(day))，\(plan.lifeCount)件生活日程，\(plan.studyCount)项\(isFiltering ? "匹配学习计划" : "学习计划")\(expenseCount > 0 ? "，已记支出 \(expenseCount) 笔" : "")\(isToday ? "，今天" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Selected day agenda

private struct ScheduleAgendaSection: View {
    let date: Date
    let tasks: [ScheduleTask]
    let allTasks: [ScheduleTask]
    let isFiltering: Bool
    let onResetFilters: () -> Void
    let onEdit: (ScheduleTask) -> Void
    let onToggle: (ScheduleTask) -> Void
    let onDelete: (ScheduleTask) -> Void
    let onAdd: () -> Void

    private var completedCount: Int { allTasks.filter(\.isCompleted).count }
    private var overlapCount: Int { SchedulePlanningHelper.overlapCount(allTasks) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Calendar.current.isDateInToday(date) ? "今日生活日程" : AppFormatters.shortDate(date) + " · 生活日程")
                    .font(.lifeSection)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(isFiltering
                     ? "显示 \(tasks.count) / \(allTasks.count) 件生活安排 · 已完成 \(completedCount) 件"
                     : "\(allTasks.count) 件生活安排 · 已完成 \(completedCount) 件")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if overlapCount > 0 {
                Label {
                    Text("当天未完成日程有 \(overlapCount) 组时间重叠，可点开任务调整。")
                        .foregroundStyle(AppTheme.textSecondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(AppTheme.coral)
                }
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }

            ScheduleTimelineList(
                tasks: tasks, isFiltering: isFiltering, onResetFilters: onResetFilters,
                onEdit: onEdit, onToggle: onToggle, onDelete: onDelete, onAdd: onAdd
            )
        }
    }
}

/// The event flag has its own row, so study totals cannot look like life events.
private struct ScheduleCalendarPlanMarks: View {
    let plan: ScheduleCalendarDayPlan

    var body: some View {
        VStack(spacing: 2) {
            if plan.hasLifeEvents {
                Label("\(plan.lifeCount)事", systemImage: "flag.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ArchiveTheme.ink)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(ArchiveTheme.goldWash, in: RoundedRectangle(cornerRadius: 4))
            } else {
                Text(" ").font(.caption2).padding(.vertical, 1)
            }
            Text(plan.studyCount > 0 ? "\(plan.studyCount)学" : " ")
                .font(.caption2)
                .foregroundStyle(ArchiveTheme.inkSoft)
        }
        .accessibilityHidden(true)
    }
}

private struct ScheduleCalendarPlanLegend: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { eventLabel; studyLabel }
            VStack(alignment: .leading, spacing: 6) { eventLabel; studyLabel }
        }
        .font(.caption)
        .foregroundStyle(ArchiveTheme.inkSoft)
        .padding(.horizontal, 2)
    }

    private var eventLabel: some View {
        Label("生活日程（含已完成）", systemImage: "flag.fill")
    }
    private var studyLabel: some View { Text("“学” · 学习计划") }
}
