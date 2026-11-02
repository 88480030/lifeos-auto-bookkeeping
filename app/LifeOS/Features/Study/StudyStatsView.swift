import SwiftUI
import Charts

struct StudyStatsView: View {
    let sessions: [StudySession]
    let dailyGoalMinutes: Int
    let onEditGoal: () -> Void

    private let calendar = Calendar.current
    private let subjectColors: [Color] = [
        AppTheme.gold, AppTheme.indigo, AppTheme.accent,
        AppTheme.coral, AppTheme.violet, AppTheme.textSecondary
    ]

    private struct SubjectSlice: Identifiable {
        let name: String
        let seconds: Int
        let color: Color
        var id: String { name }
    }

    private struct TrendPoint: Identifiable {
        let day: Date
        let minutes: Int
        var id: Date { day }
    }

    private var todayTotals: StudyTotals {
        StudyAnalytics.totals(sessions, on: .now, calendar: calendar)
    }

    private var weekTotals: StudyTotals {
        StudyAnalytics.totals(sessions, in: StudyAnalytics.weekInterval(containing: .now, calendar: calendar))
    }

    private var monthTotals: StudyTotals {
        StudyAnalytics.totals(sessions, in: StudyAnalytics.monthInterval(containing: .now, calendar: calendar))
    }

    private var streak: Int {
        StudyAnalytics.streak(sessions, calendar: calendar, now: .now)
    }

    private var trendPoints: [TrendPoint] {
        let end = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -13, to: end) ?? end
        let interval = DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: end) ?? end)
        let totals = StudyAnalytics.dailyTotals(sessions, in: interval, calendar: calendar)
        let lookup = Dictionary(uniqueKeysWithValues: totals.map { (calendar.startOfDay(for: $0.day), $0.focusedSeconds) })

        var points: [TrendPoint] = []
        var day = start
        while day <= end {
            points.append(
                TrendPoint(
                    day: day,
                    minutes: (lookup[day] ?? 0) / 60
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }

    private var subjectSlices: [SubjectSlice] {
        let monthInterval = StudyAnalytics.monthInterval(containing: .now, calendar: calendar)
        return StudyAnalytics.subjectTotals(sessions, in: monthInterval)
            .enumerated()
            .map { index, total in
                SubjectSlice(
                    name: total.subject,
                    seconds: total.focusedSeconds,
                    color: subjectColors[index % subjectColors.count]
                )
            }
    }

    private var totalMonthSubjectSeconds: Int {
        subjectSlices.reduce(0) { $0 + $1.seconds }
    }

    private var goalProgress: Double {
        StudyAnalytics.goalProgress(focusedSeconds: todayTotals.focusedSeconds, dailyGoalMinutes: dailyGoalMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            metricsGrid
            trendCard
            subjectCard
            goalCard

            if sessions.isEmpty {
                SurfaceCard {
                    EmptyStateView(
                        icon: "chart.bar",
                        title: "还没有学习记录",
                        message: "完成一次专注后，这里会出现真实的统计图表。"
                    )
                }
            }
        }
    }

    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline) {
                Text("STUDY DASHBOARD")
                    .font(.archiveMonoStrong)
                    .tracking(1.0)
                    .foregroundStyle(ArchiveTheme.gold)
                Spacer()
                Text("SWIPE →")
                    .font(.archiveMono)
                    .foregroundStyle(ArchiveTheme.inkMuted)
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    StudyMetricCard(
                        title: "Today",
                        value: "\(todayTotals.minutes)",
                        unit: "分钟",
                        tint: AppTheme.gold
                    )
                    .frame(width: 168)

                    StudyMetricCard(
                        title: "This Week",
                        value: "\(weekTotals.minutes)",
                        unit: "分钟",
                        tint: AppTheme.indigo
                    )
                    .frame(width: 168)

                    StudyMetricCard(
                        title: "This Month",
                        value: "\(monthTotals.minutes)",
                        unit: "分钟",
                        tint: AppTheme.accent
                    )
                    .frame(width: 168)

                    StudyMetricCard(
                        title: "Pomodoros",
                        value: "\(todayTotals.pomodoroCount)",
                        unit: "个",
                        tint: AppTheme.coral
                    )
                    .frame(width: 168)
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var trendCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "Trend")
                        Text("最近 14 天学习时长")
                            .font(.lifeCard)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    Spacer()
                    Text("单位：分钟")
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                if trendPoints.allSatisfy({ $0.minutes == 0 }) {
                    EmptyStateView(
                        icon: "chart.bar",
                        title: "暂无学习数据",
                        message: "完成专注后自动生成趋势。"
                    )
                } else {
                    Chart(trendPoints) { point in
                        BarMark(
                            x: .value("日期", point.day, unit: .day),
                            y: .value("分钟", point.minutes)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.gold.opacity(0.9), AppTheme.goldBright.opacity(0.75)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                            AxisValueLabel(format: .dateTime.month().day())
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 160)
                }
            }
        }
    }

    private var subjectCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "Subjects")
                        Text("科目占比")
                            .font(.lifeCard)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    Spacer()
                    if totalMonthSubjectSeconds > 0 {
                        Text("\(totalMonthSubjectSeconds / 60) 分钟")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                if subjectSlices.isEmpty {
                    EmptyStateView(
                        icon: "chart.pie",
                        title: "暂无科目数据",
                        message: "给学习任务设置科目后，这里会自动汇总。"
                    )
                } else {
                    HStack(spacing: 18) {
                        Chart(subjectSlices) { slice in
                            SectorMark(
                                angle: .value("时长", Double(slice.seconds)),
                                innerRadius: .ratio(0.62),
                                angularInset: 2
                            )
                            .cornerRadius(4)
                            .foregroundStyle(slice.color)
                        }
                        .frame(width: 145, height: 145)

                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(subjectSlices.prefix(5)) { slice in
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(slice.color)
                                        .frame(width: 7, height: 7)
                                    Text(slice.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(Int((Double(slice.seconds) / Double(max(1, totalMonthSubjectSeconds)) * 100).rounded()))%")
                                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(AppTheme.textTertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var goalCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "Goal")
                        Text("今日目标完成率")
                            .font(.lifeCard)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    Spacer()
                    Button {
                        Haptics.tap()
                        onEditGoal()
                    } label: {
                        Text("调整")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.gold)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule(style: .continuous).fill(AppTheme.gold.opacity(0.10)))
                            .overlay(Capsule(style: .continuous).strokeBorder(AppTheme.gold.opacity(0.30), lineWidth: 0.8))
                    }
                    .buttonStyle(PressableScaleStyle())
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(AppFormatters.percent(goalProgress))
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                        .foregroundStyle(goalProgress >= 1 ? AppTheme.accent : AppTheme.textPrimary)
                    Text("· 连续 \(streak) 天")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                ProgressBar(progress: goalProgress, tint: goalProgress >= 1 ? AppTheme.accent : AppTheme.gold)
                Text("今日 \(todayTotals.minutes) / \(dailyGoalMinutes) 分钟")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }
}
