import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

@main
struct LifeOSActivityBundle: WidgetBundle {
    var body: some Widget {
        StudyActivityWidget()
        LifeOSTodayWidget()
        LifeOSSpendingWidget()
        LifeOSFocusWidget()
    }
}

struct StudyActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudyActivityAttributes.self) { context in
            StudyLockScreenActivity(context: context)
                .activityBackgroundTint(StudyActivityPalette.paper)
                .activitySystemActionForegroundColor(StudyActivityPalette.ink)
                .widgetURL(StudyActivityPresentation.openURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(StudyActivityPresentation.title(context), systemImage: StudyActivityPresentation.icon(context))
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(StudyActivityPalette.islandAccent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StudyActivityTime(state: context.state, expired: StudyActivityPresentation.isExpired(context))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 62, alignment: .trailing)
                }
            } compactLeading: {
                Image(systemName: StudyActivityPresentation.icon(context))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StudyActivityPalette.islandAccent)
                    .accessibilityLabel(StudyActivityPresentation.title(context))
            } compactTrailing: {
                StudyActivityTime(state: context.state, expired: StudyActivityPresentation.isExpired(context))
                    .font(.caption2.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .foregroundStyle(StudyActivityPalette.islandAccent)
                    .frame(width: 52, alignment: .trailing)
            } minimal: {
                Image(systemName: StudyActivityPresentation.icon(context))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StudyActivityPalette.islandAccent)
                    .accessibilityLabel(StudyActivityPresentation.title(context))
            }
            .widgetURL(StudyActivityPresentation.openURL)
            .keylineTint(StudyActivityPalette.islandAccent)
        }
    }
}

private struct StudyLockScreenActivity: View {
    let context: ActivityViewContext<StudyActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Label(StudyActivityPresentation.title(context), systemImage: StudyActivityPresentation.icon(context))
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 12)
            StudyActivityTime(state: context.state, expired: StudyActivityPresentation.isExpired(context))
                .font(.headline)
                .frame(width: 72, alignment: .trailing)
        }
        .foregroundStyle(StudyActivityPalette.ink)
        .padding(14)
        .accessibilityHint("轻点打开 LifeOS 专注页")
    }
}

private struct StudyActivityTime: View {
    let state: StudyActivityAttributes.ContentState
    let expired: Bool

    var body: some View {
        Group {
            if expired {
                Text("00:00")
            } else if state.isPaused {
                Text(Self.formatted(state.remainingSeconds))
            } else {
                Text(timerInterval: state.startAt...max(state.startAt, state.endAt), countsDown: true, showsHours: false)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private static func formatted(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private enum StudyActivityPresentation {
    static let openURL = URL(string: "lifeos://study")!

    static func isExpired(_ context: ActivityViewContext<StudyActivityAttributes>) -> Bool {
        !context.state.isPaused && (context.isStale || context.state.endAt <= .now)
    }

    static func title(_ context: ActivityViewContext<StudyActivityAttributes>) -> String {
        if isExpired(context) { return "本轮已到时" }
        return context.state.isPaused ? "\(context.state.phaseTitle)已暂停" : context.state.phaseTitle
    }

    static func icon(_ context: ActivityViewContext<StudyActivityAttributes>) -> String {
        if isExpired(context) { return "checkmark.circle.fill" }
        if context.state.isPaused { return "pause.circle.fill" }
        return context.state.phase == "focus" ? "timer" : "leaf.fill"
    }

}

private enum StudyActivityPalette {
    static let paper = adaptive(light: 0xF6F0E2, dark: 0x0D1713)
    static let ink = adaptive(light: 0x16382F, dark: 0xF3EEE3)
    static let islandAccent = Color(red: 191.0 / 255, green: 224.0 / 255, blue: 207.0 / 255)

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
