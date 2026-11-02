import SwiftUI
import UIKit
import WidgetKit

/// The widgets read an explicitly shared projection; they never open the app database.
private struct LifeOSWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: LifeOSWidgetSnapshot?
}

private struct LifeOSWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LifeOSWidgetEntry {
        LifeOSWidgetEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (LifeOSWidgetEntry) -> Void) {
        completion(LifeOSWidgetEntry(date: .now, snapshot: LifeOSWidgetStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LifeOSWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = LifeOSWidgetStore.read()
        var boundaryDates: [Date] = []
        if let snapshot, snapshot.isCurrentDay(at: now) {
            boundaryDates.append(snapshot.dayEnd)
            if snapshot.focus.state == "running", let end = snapshot.focus.endAt, end > now {
                boundaryDates.append(end)
            }
        }
        let boundaries = Array(Set(boundaryDates)).sorted()
        let entries = [LifeOSWidgetEntry(date: now, snapshot: snapshot)] + boundaries.map {
            LifeOSWidgetEntry(date: $0, snapshot: snapshot)
        }
        // A successful app write actively reloads the widgets. The slow fallback also
        // recovers a newly available shared container without frequent polling.
        let refresh = min(boundaries.last?.addingTimeInterval(60) ?? now.addingTimeInterval(3600),
                          now.addingTimeInterval(6 * 3600))
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct LifeOSTodayWidget: Widget {
    let kind = "LifeOSTodayWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LifeOSWidgetProvider()) { entry in
            LifeOSTodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.paper }
                .widgetURL(URL(string: "lifeos://schedule"))
        }
        .configurationDisplayName("今日待办")
        .description("查看今天的待办和完成情况。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LifeOSSpendingWidget: Widget {
    let kind = "LifeOSSpendingWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LifeOSWidgetProvider()) { entry in
            LifeOSSpendingWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.paper }
                .widgetURL(URL(string: "lifeos://finance"))
        }
        .configurationDisplayName("今日消费")
        .description("查看今天记录的人民币支出。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LifeOSFocusWidget: Widget {
    let kind = "LifeOSFocusWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LifeOSWidgetProvider()) { entry in
            LifeOSFocusWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.paper }
                .widgetURL(URL(string: "lifeos://study"))
        }
        .configurationDisplayName("专注计时")
        .description("查看当前专注或休息计时。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct WidgetHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.caption2.weight(.medium))
                .accessibilityHidden(true)
        }
        .foregroundStyle(WidgetPalette.ink)
    }
}

private struct WidgetNeedsSync: View {
    let title: String
    let symbol: String
    let expired: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: title, symbol: symbol)
            Spacer(minLength: 8)
            Text(expired ? "打开 LifeOS 更新今天" : "打开 LifeOS 同步数据")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(WidgetPalette.ink)
            Text("轻点进入")
                .font(.caption)
                .foregroundStyle(WidgetPalette.soft)
                .padding(.top, 5)
            Spacer(minLength: 0)
        }
    }
}

private struct LifeOSTodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LifeOSWidgetEntry

    var body: some View {
        if let data = entry.snapshot, data.isCurrentDay(at: entry.date) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(title: "今日待办", symbol: "calendar")
                Spacer(minLength: 5)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(data.pendingCount)")
                        .font(.system(size: 33, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("项待完成")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(WidgetPalette.ink)
                .accessibilityElement(children: .combine)
                .privacySensitive()
                .padding(.bottom, 5)
                Rectangle().fill(WidgetPalette.rule).frame(height: 1)
                Spacer(minLength: 5)
                if data.pendingTasks.isEmpty {
                    Text("今天没有待完成的日程")
                        .font(.caption)
                        .foregroundStyle(WidgetPalette.soft)
                        .lineLimit(2)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(data.pendingTasks.prefix(family == .systemSmall ? 1 : 2).enumerated()), id: \.offset) { _, task in
                            HStack(spacing: 5) {
                                Image(systemName: "circle")
                                    .font(.system(size: 8, weight: .semibold))
                                    .accessibilityHidden(true)
                                Text(task.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .privacySensitive()
                                Spacer(minLength: 0)
                                if family != .systemSmall {
                                    Text(task.startAt, format: .dateTime.hour().minute())
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(WidgetPalette.soft)
                                        .privacySensitive()
                                }
                            }
                        }
                    }
                    .foregroundStyle(WidgetPalette.ink)
                }
                if family != .systemSmall {
                    Text("已完成 \(data.completedCount) 项")
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.soft)
                        .privacySensitive()
                        .padding(.top, 4)
                }
            }
        } else {
            WidgetNeedsSync(title: "今日待办", symbol: "calendar", expired: entry.snapshot != nil)
        }
    }
}

private struct LifeOSSpendingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LifeOSWidgetEntry

    var body: some View {
        if let data = entry.snapshot, data.isCurrentDay(at: entry.date) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(title: "今日消费", symbol: "creditcard")
                Spacer(minLength: 5)
                HStack(alignment: .center, spacing: 4) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(amount(data.todayExpenseMinor))
                            .font(.system(size: family == .systemSmall ? 25 : 31, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .foregroundStyle(WidgetPalette.ink)
                            .privacySensitive()
                        Text(data.todayExpenseCount == 0 ? "今天还没有支出" : "今天记录 \(data.todayExpenseCount) 笔支出")
                            .font(.caption)
                            .foregroundStyle(WidgetPalette.soft)
                            .lineLimit(2)
                            .privacySensitive()
                    }
                    Spacer(minLength: 0)
                    Image(avatar(data.todayExpenseMinor))
                        .resizable()
                        .scaledToFit()
                        .frame(width: family == .systemSmall ? 45 : 90,
                               height: family == .systemSmall ? 45 : 90)
                        .accessibilityHidden(true)
                        .privacySensitive()
                }
                Spacer(minLength: 0)
                Text("人民币 · 实际支出")
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.soft)
            }
        } else {
            WidgetNeedsSync(title: "今日消费", symbol: "creditcard", expired: entry.snapshot != nil)
        }
    }

    private func amount(_ minor: Int) -> String {
        (Decimal(minor) / Decimal(100)).formatted(.currency(code: "CNY").locale(Locale(identifier: "zh_CN")))
    }

    private func avatar(_ minor: Int) -> String {
        switch minor {
        case ...2000: "MascotOtter"
        case ...3000: "MascotBear"
        case ...4000: "MascotRabbit"
        case ...5000: "MascotCat"
        default: "MascotFox"
        }
    }
}

private struct LifeOSFocusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LifeOSWidgetEntry

    var body: some View {
        if let data = entry.snapshot, data.isCurrentDay(at: entry.date) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(title: "专注计时", symbol: "timer")
                Spacer(minLength: 4)
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(status(data.focus))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(WidgetPalette.soft)
                            .lineLimit(1)
                        focusTime(data.focus)
                            .font(.system(size: family == .systemSmall ? 25 : 31, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(WidgetPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(detail(data.focus))
                            .font(.caption2)
                            .foregroundStyle(WidgetPalette.soft)
                            .lineLimit(family == .systemSmall ? 1 : 2)
                            .privacySensitive()
                    }
                    Spacer(minLength: 0)
                    Image("MascotOtter")
                        .resizable()
                        .scaledToFit()
                        .frame(width: family == .systemSmall ? 50 : 95,
                               height: family == .systemSmall ? 60 : 95)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
        } else {
            WidgetNeedsSync(title: "专注计时", symbol: "timer", expired: entry.snapshot != nil)
        }
    }

    @ViewBuilder private func focusTime(_ focus: LifeOSWidgetFocus) -> some View {
        if focus.state == "running", let end = focus.endAt, end > entry.date {
            Text(timerInterval: entry.date...end, countsDown: true, showsHours: false)
        } else if focus.state == "paused" {
            Text(formattedTime(focus.remainingSeconds))
        } else if focus.state == "running", focus.endAt != nil {
            Text("00:00")
        } else {
            Text("--:--")
        }
    }

    private func status(_ focus: LifeOSWidgetFocus) -> String {
        if focus.state == "running", let end = focus.endAt, end <= entry.date { return "本轮已到时" }
        if focus.state == "idle" { return "准备好再开始" }
        if focus.state == "running", focus.endAt == nil { return "打开 App 同步" }
        let phase = switch focus.phase {
        case "shortBreak": "短休息"
        case "longBreak": "长休息"
        default: "专注"
        }
        return focus.state == "paused" ? "\(phase)已暂停" : "\(phase)中"
    }

    private func detail(_ focus: LifeOSWidgetFocus) -> String {
        if focus.state == "running", let end = focus.endAt, end <= entry.date { return "打开 App 同步下一阶段" }
        if focus.state == "running", focus.endAt == nil { return "轻点回到专注页" }
        if focus.state == "idle" { return "轻点打开专注页" }
        return focus.taskTitle?.isEmpty == false ? focus.taskTitle! : "轻点打开专注页"
    }

    private func formattedTime(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private enum WidgetPalette {
    static let paper = adaptive(light: 0xF6F0E2, dark: 0x0D1713)
    static let ink = adaptive(light: 0x16382F, dark: 0xF3EEE3)
    static let soft = adaptive(light: 0x4D655B, dark: 0xB8C8BE)
    static let rule = adaptive(light: 0xD9CEB8, dark: 0x2D3D34)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}
