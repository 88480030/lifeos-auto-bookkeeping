import SwiftUI

// MARK: - Section

enum StudySection: String, CaseIterable, Identifiable {
    case timer
    case tasks
    case stats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timer: "专注"
        case .tasks: "任务"
        case .stats: "统计"
        }
    }
}

struct StudySegmentedControl: View {
    @Binding var selection: StudySection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StudySection.allCases) { section in
                Button {
                    guard selection != section else { return }
                    Haptics.select()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        selection = section
                    }
                } label: {
                    Text(section.title)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(selection == section ? ArchiveTheme.ink : ArchiveTheme.inkSoft)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background {
                            if selection == section {
                                Capsule(style: .continuous)
                                    .fill(ArchiveTheme.mintWash)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(ArchiveTheme.ink.opacity(0.8), lineWidth: 1.1)
                                    )
                                    .matchedGeometryEffect(id: "studySection", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule(style: .continuous).fill(ArchiveTheme.paperRaised))
        .overlay(Capsule(style: .continuous).strokeBorder(ArchiveTheme.ink.opacity(0.7), lineWidth: 1.4))
    }
}

// MARK: - Timer ring

struct StudyTimerRing: View {
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.separator.opacity(0.55), lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint, AppTheme.goldBright, tint],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Metric card

struct StudyMetricCard: View {
    let title: String
    let value: String
    let unit: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(text: title, tint: tint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let unit {
                    Text(unit)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.tileRadius, style: .continuous)
                .fill(AppTheme.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.tileRadius, style: .continuous)
                .strokeBorder(ArchiveTheme.ink.opacity(0.7), lineWidth: 1.4)
        )
    }
}

// MARK: - Task row

struct StudyTaskRow: View {
    let task: StudyTask
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onFocus: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var plannedDateLabel: String? {
        guard let date = task.plannedDate else { return nil }
        if Calendar.current.isDateInToday(date) { return "今天" }
        if !task.isCompleted && date < Calendar.current.startOfDay(for: .now) {
            return "逾期 · " + AppFormatters.shortDate(date)
        }
        return AppFormatters.shortDate(date)
    }

    private var isOverdue: Bool {
        !task.isCompleted && (task.plannedDate.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button(action: onToggle) {
                CompletionToggleMark(isCompleted: task.isCompleted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "将“\(task.title)”标记为未完成" : "完成“\(task.title)”")

            VStack(alignment: .leading, spacing: 6) {
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title)
                            .font(.subheadline.weight(.medium))
                            .strikethrough(task.isCompleted)
                            .foregroundStyle(task.isCompleted ? ArchiveTheme.inkSoft : ArchiveTheme.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .contentTransition(.opacity)
                            .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.18), value: task.isCompleted)
                        Text("\(task.subject.isEmpty ? "未分类" : task.subject) · 预计 \(task.estimatedMinutes) 分钟")
                            .font(.caption)
                            .foregroundStyle(ArchiveTheme.inkSoft)
                            .multilineTextAlignment(.leading)
                        if let plannedDateLabel {
                            Label(plannedDateLabel + (task.plannedTimeRange.map { " · " + $0 } ?? ""), systemImage: isOverdue ? "exclamationmark.circle" : "calendar")
                                .font(.caption)
                                .foregroundStyle(isOverdue ? ArchiveTheme.coral : ArchiveTheme.inkSoft)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("编辑学习任务")

                if !task.isCompleted {
                    Button(action: onFocus) {
                        Label("专注", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ArchiveTheme.ink)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(ArchiveTheme.mintWash))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择“\(task.title)”并打开专注计时")
                }
            }
            .padding(.vertical, 8)
        }
        .padding(.leading, 7)
        .padding(.trailing, 16)
        .padding(.vertical, 7)
        .background {
            ArchiveTheme.mintWash
                .opacity(task.isCompleted ? 0.65 : 0)
                .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.20), value: task.isCompleted)
        }
        .contextMenu {
            if !task.isCompleted {
                Button(action: onFocus) { Label("选择并专注", systemImage: "play.fill") }
            }
            Button(action: onEdit) { Label("编辑", systemImage: "pencil") }
            Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
        }
    }
}
