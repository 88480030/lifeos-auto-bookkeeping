import SwiftUI
import UIKit

struct StudyFocusView: View {
    @ObservedObject var timer: StudyTimerEngine
    let tasks: [StudyTask]
    @Binding var selectedTaskID: UUID?
    let todayMinutes: Int
    let pomodoroCount: Int
    let onAddTask: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingEndConfirmation = false
    @State private var taskDetailsExpanded = false
    @State private var companionReply: String?

    private var selectedTask: StudyTask? {
        tasks.first { $0.id == selectedTaskID && !$0.isCompleted }
    }

    private var taskDateLabel: String {
        let prefix = timer.isIdle ? "关联学习任务" : "下一轮学习任务"
        guard let task = selectedTask else { return prefix }
        guard let date = task.plannedDate else { return prefix + " · 未排期" }
        return prefix + " · " + (Calendar.current.isDateInToday(date) ? "今天" : AppFormatters.shortDate(date)) + (task.plannedTimeRange.map { " · " + $0 } ?? "")
    }

    private var activeTaskTitle: String? {
        timer.isIdle ? selectedTask?.title : timer.machine.taskTitle
    }

    private var companionMood: AnyaPomodoroMood {
        if timer.isPaused { return .paused }
        if timer.phase != .focus { return .rest }
        if timer.isRunning { return .focus }
        return .ready
    }

    private var cuteTint: Color {
        switch timer.phase {
        case .focus: Color(hex: 0xE96A5E)
        case .shortBreak: ArchiveTheme.mintDeep
        case .longBreak: ArchiveTheme.gold
        }
    }

    private var timerFill: Color {
        if timer.isPaused { return ArchiveTheme.goldWash }
        if timer.phase == .focus { return ArchiveTheme.pinkWash }
        return ArchiveTheme.mintWash
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            timerCard
            taskCard

            if timer.notificationDenied {
                notificationBanner
            }

            Text("锁屏或退到后台后，计时会按时间戳继续；回来时会自动校准并记录。")
                .font(.caption)
                .foregroundStyle(ArchiveTheme.inkSoft)
                .padding(.horizontal, 4)
        }
        .confirmationDialog("结束本轮专注？", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("结束并保留记录", role: .destructive) { timer.end() }
            Button("继续专注", role: .cancel) {}
        } message: {
            Text("已经完成的专注时长会保留为学习记录。")
        }
        .onChange(of: companionMood) { _, _ in companionReply = nil }
        .task(id: companionReply) {
            guard companionReply != nil else { return }
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            companionReply = nil
        }
    }

    // MARK: Timer card

    private var timerCard: some View {
        MangaPanel(
            fill: timerFill,
            borderWidth: 2.4,
            cornerRadius: 18,
            padding: 18
        ) {
            VStack(spacing: 12) {
                let headerLayout = dynamicTypeSize >= .xxxLarge
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                headerLayout {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(timer.isIdle ? "小水獭陪你专注" : timer.phase.displayName + (timer.isPaused ? " · 已暂停" : ""))
                            .font(.system(.title3, design: .rounded).weight(.black))
                            .foregroundStyle(ArchiveTheme.ink)

                        Text(timer.isIdle ? "选一个目标，留一段时间给自己" : timer.isPaused ? "计时已暂停，准备好后再继续" : timer.phase == .focus ? "专注进行中，结束后自动进入休息" : "休息结束后，自行开始下一轮")
                            .font(.caption)
                            .foregroundStyle(ArchiveTheme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("第 \(timer.cycleIndex + 1)/\(timer.longBreakEvery) 轮")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(ArchiveTheme.inkSoft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(ArchiveTheme.paperRaised, in: Capsule())
                }

                companionClock

                companionCaption

                let controlsLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 10))
                    : AnyLayout(HStackLayout(spacing: 10))
                controlsLayout {
                    primaryButton
                    secondaryButton
                }

                cycleDots

                if let status = timer.statusMessage {
                    Text(status)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(cuteTint)
                        .transition(.opacity)
                }
            }
        }
    }

    private var companionCaption: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Text(companionReply ?? companionMood.line)
            } else {
                Text(companionReply ?? companionMood.line)
                    .lineLimit(2, reservesSpace: true)
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(ArchiveTheme.inkSoft)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var companionClock: some View {
        VStack(spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    ZStack {
                        CutePomodoroRing(progress: timer.progress, tint: cuteTint)
                            .frame(width: 228, height: 228)
                            .scaleEffect(0.76)
                        interactiveCompanion
                            .frame(width: 150, height: 170)
                    }
                    .frame(height: 178)
                    countdown(fontSize: nil)
                    phaseLabel
                    activeTaskLabel
                }
            } else {
                GeometryReader { proxy in
                    let diameter = min(proxy.size.width, 260)
                    ZStack {
                        CutePomodoroRing(progress: timer.progress, tint: cuteTint)
                            .frame(width: 228, height: 228)
                            .scaleEffect(diameter / 228)

                        VStack(spacing: 3) {
                            interactiveCompanion
                                .frame(width: diameter * 0.74, height: diameter * 0.66)
                            countdown(fontSize: min(42, diameter * 0.16))
                        }
                        .frame(width: diameter * 0.74)
                    }
                    .frame(width: diameter, height: diameter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 260)
                .frame(maxWidth: .infinity)

                activeTaskLabel
            }
        }
    }

    private var interactiveCompanion: some View {
        AnyaPomodoroCompanion(mood: companionMood, onReact: {
            companionReply = timer.isPaused ? "收到，准备好后再一起出发。" : timer.isRunning ? "小水獭收到！这一轮一起完成。" : "小水獭准备好了，开始吧！"
        })
    }

    private func countdown(fontSize: CGFloat?) -> some View {
        Text(timeString)
            .font(fontSize.map { .system(size: $0, weight: .black, design: .rounded) }
                ?? .system(.largeTitle, design: .rounded).weight(.black))
            .monospacedDigit()
            .foregroundStyle(ArchiveTheme.ink)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(timer.isIdle ? "待开始的专注计时" : timer.phase.displayName + (timer.isPaused ? "，已暂停" : "，进行中"))
            .accessibilityValue("剩余 \(max(0, timer.remainingSeconds) / 60) 分 \(max(0, timer.remainingSeconds) % 60) 秒")
    }

    private var phaseLabel: some View {
        Text(timer.isIdle ? "\(timer.preferences.focusMinutes) 分钟专注" : timer.phase.displayName + (timer.isPaused ? " · 已暂停" : ""))
            .font(.caption.weight(.semibold))
            .foregroundStyle(ArchiveTheme.inkSoft)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var activeTaskLabel: some View {
        if let taskTitle = activeTaskTitle {
            Text(taskTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ArchiveTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    private var timeString: String {
        let seconds = max(0, timer.remainingSeconds)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var cycleDots: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            HStack(spacing: 4) {
                ForEach(0..<timer.longBreakEvery, id: \.self) { index in
                    TomatoDot(filled: index < timer.cycleIndex)
                }
            }
            Text("今日 \(todayMinutes) 分钟 · \(pomodoroCount) 个番茄")
                .font(.caption.weight(.medium))
                .foregroundStyle(ArchiveTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日已专注 \(todayMinutes) 分钟，完成 \(pomodoroCount) 个番茄；当前第 \(timer.cycleIndex + 1) 轮，共 \(timer.longBreakEvery) 轮")
    }

    @ViewBuilder
    private var primaryButton: some View {
        Button {
            if timer.isIdle {
                timer.startFocus(task: selectedTask)
            } else if timer.isRunning {
                timer.pause()
            } else {
                timer.resume()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: timer.isIdle ? "play.fill" : (timer.isRunning ? "pause.fill" : "play.fill"))
                    .font(.caption.weight(.semibold))
                Text(timer.isIdle ? "开始专注" : (timer.isRunning ? "暂停" : "继续"))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(ArchiveTheme.stripInk)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
            .background(
                Capsule(style: .continuous)
                    .fill(ArchiveTheme.strip)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(ArchiveTheme.ink.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(PressableScaleStyle())
    }

    @ViewBuilder
    private var secondaryButton: some View {
        Button {
            if timer.phase == .focus {
                showingEndConfirmation = true
            } else {
                timer.end()
            }
        } label: {
            Text(timer.phase == .focus ? "结束" : "结束休息")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
                .background(Capsule(style: .continuous).fill(AppTheme.surface.opacity(0.55)))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AppTheme.separator.opacity(0.75), lineWidth: 0.8)
                )
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(timer.isIdle)
        .opacity(timer.isIdle ? 0.35 : 1)
    }

    // MARK: Task

    private var taskCard: some View {
        SurfaceCard(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    Haptics.select()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88)) {
                        taskDetailsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "book.closed")
                            .font(.title3)
                            .foregroundStyle(ArchiveTheme.mintDeep)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(taskDateLabel)
                                .font(.caption)
                                .foregroundStyle(ArchiveTheme.inkSoft)
                            Text(selectedTask?.title ?? "自由专注")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ArchiveTheme.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ArchiveTheme.inkSoft)
                            .rotationEffect(.degrees(taskDetailsExpanded ? 180 : 0))
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel((taskDetailsExpanded ? "收起" : "展开") + "学习任务选择")
                .accessibilityValue(selectedTask?.title ?? "自由专注")

                if taskDetailsExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedTask.map { "\($0.subject.isEmpty ? "未分类" : $0.subject) · 预计 \($0.estimatedMinutes) 分钟" } ?? "专注时长照常记录，不关联具体任务")
                        .font(.caption)
                        .foregroundStyle(ArchiveTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    Menu {
                        Button("自由专注，不关联任务") { selectedTaskID = nil }
                        Divider()
                        ForEach(tasks.filter { !$0.isCompleted }) { task in
                            Button(task.title) { selectedTaskID = task.id }
                        }
                        Divider()
                        Button(action: onAddTask) { Label("新建学习任务", systemImage: "plus") }
                    } label: {
                        Label(selectedTask == nil ? "选择任务" : "更换任务", systemImage: "chevron.up.chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ArchiveTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(ArchiveTheme.mintWash))
                            .overlay(Capsule().strokeBorder(ArchiveTheme.rule, lineWidth: 1))
                    }
                    .accessibilityLabel(timer.isIdle ? "选择关联的学习任务" : "选择下一轮学习任务")

                    if !timer.isIdle {
                        Text("本轮记录：\(timer.machine.taskTitle ?? "自由专注")。更换任务从下一轮生效。")
                            .font(.caption)
                            .foregroundStyle(ArchiveTheme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if tasks.allSatisfy({ $0.isCompleted }) {
                        Text("还没有待完成的任务？在上方菜单中新建，也可以直接开始自由专注。")
                            .font(.caption)
                            .foregroundStyle(ArchiveTheme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 14)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .clipped()
        }
    }

    private var notificationBanner: some View {
        SurfaceCard(padding: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.coral)

                Text("通知未开启：锁屏时计时结束不会提醒")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ArchiveTheme.ink)
                .frame(minHeight: 44)
            }
        }
    }
}
