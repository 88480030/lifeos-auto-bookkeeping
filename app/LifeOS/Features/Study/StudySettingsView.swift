import SwiftUI
import UIKit

struct StudySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @ObservedObject var timer: StudyTimerEngine
    @ObservedObject private var liveActivity = StudyLiveActivityController.shared

    @State private var draft: StudyPreferences

    init(timer: StudyTimerEngine) {
        self.timer = timer
        _draft = State(initialValue: timer.preferences)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("专注节奏").font(.headline).foregroundStyle(ArchiveTheme.ink)
                            stepperRow(title: "专注时长", value: $draft.focusMinutes, range: 5...90, step: 5, unit: "分钟")
                            stepperRow(title: "短休息", value: $draft.shortBreakMinutes, range: 1...30, step: 1, unit: "分钟")
                            stepperRow(title: "长休息", value: $draft.longBreakMinutes, range: 5...60, step: 5, unit: "分钟")
                            stepperRow(title: "每几轮长休息", value: $draft.longBreakEvery, range: 2...8, step: 1, unit: "轮")
                        }
                    }

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("每日目标").font(.headline).foregroundStyle(ArchiveTheme.ink)
                            stepperRow(title: "每日学习目标", value: $draft.dailyGoalMinutes, range: 10...300, step: 10, unit: "分钟")
                        }
                    }

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("灵动岛与锁屏", isOn: Binding(
                                get: { liveActivity.isEnabled },
                                set: { timer.setLiveActivityEnabled($0) }
                            ))
                            .font(.headline)
                            .tint(ArchiveTheme.mintDeep)
                            .frame(minHeight: 44)

                            Text(liveActivity.statusMessage)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if liveActivity.isEnabled && !liveActivity.systemAllowsActivities {
                                Button("打开系统设置") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                }
                                .frame(minHeight: 44)
                            } else if liveActivity.isEnabled && !timer.isIdle {
                                Button("重新显示本轮实时活动") { timer.retryLiveActivity() }
                                    .frame(minHeight: 44)
                            }

                            Text("灵动岛仅显示状态图标和倒计时。轻点回到专注页操作；到时后打开 LifeOS，同步下一阶段。")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("结束提醒").font(.headline).foregroundStyle(ArchiveTheme.ink)

                            if timer.notificationDenied {
                                HStack(spacing: 8) {
                                    Image(systemName: "bell.slash.fill")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(AppTheme.coral)
                                    Text("通知权限未开启，锁屏时计时结束不会提醒。")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Button("打开系统设置") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        openURL(url)
                                    }
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.gold)
                            } else {
                                Text("计时开始时会请求通知权限。允许后，锁屏或 App 关闭也能准时提醒。")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }

                    Text("修改后的时长从下一次开始生效；正在进行的计时不受影响。")
                        .font(.caption)
                        .foregroundStyle(ArchiveTheme.inkSoft)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            Button {
                timer.updatePreferences(draft)
                Haptics.success()
                dismiss()
            } label: {
                Text("保存设置")
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
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background { AppBackground() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
            .accessibilityLabel("关闭番茄钟设置")

            Spacer()

            Text("番茄钟设置")
                .font(.system(.headline, design: .serif).weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func stepperRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        unit: String
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text("\(value.wrappedValue) \(unit)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(AppTheme.gold)
            Stepper(title, value: value, in: range, step: step)
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityValue("\(value.wrappedValue) \(unit)")
        }
    }
}
