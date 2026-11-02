import SwiftUI
import UIKit

// MARK: - Haptics

enum Haptics {
    @MainActor
    static func tap() {
        guard UserDefaults.standard.object(forKey: "lifeos.haptics") as? Bool != false else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }

    @MainActor
    static func select() {
        guard UserDefaults.standard.object(forKey: "lifeos.haptics") as? Bool != false else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @MainActor
    static func success() {
        guard UserDefaults.standard.object(forKey: "lifeos.haptics") as? Bool != false else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Press

struct PressableScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.982 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - AppBackground

struct AppBackground: View {
    var body: some View {
        ArchiveBackground()
    }
}

// MARK: - SurfaceCard

struct SurfaceCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)

        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(AppTheme.surface))
            .overlay(shape.strokeBorder(ArchiveTheme.ink.opacity(colorScheme == .dark ? 0.72 : 0.82), lineWidth: 1.5))
            .clipShape(shape)
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.08),
                radius: 0,
                x: 2,
                y: 3
            )
    }
}

// MARK: - Eyebrow

struct Eyebrow: View {
    let text: String
    var tint: Color = AppTheme.gold

    var body: some View {
        Text(text.uppercased())
            .font(.lifeEyebrow)
            .tracking(1.8)
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

// MARK: - Hairline

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, AppTheme.gold.opacity(0.42), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.8)
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String
    var eyebrow: String?
    var trailing: String?

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                if let eyebrow {
                    Eyebrow(text: eyebrow)
                }
                Text(title)
                    .font(.lifeSection)
                    .foregroundStyle(AppTheme.textPrimary)
            }
            Spacer(minLength: 12)
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }
}

// MARK: - Badges

struct PillBadge: View {
    let text: String
    var tint: Color = AppTheme.gold

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.10)))
            .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.34), lineWidth: 0.7))
    }
}

struct PriorityBadge: View {
    let priority: TaskPriority

    var body: some View {
        PillBadge(text: priority.displayName, tint: tint)
    }

    private var tint: Color {
        switch priority {
        case .urgent: AppTheme.coral
        case .high: AppTheme.gold
        case .normal: AppTheme.accent
        case .low: AppTheme.textTertiary
        }
    }
}

// MARK: - Progress

struct ProgressBar: View {
    let progress: Double
    var tint: Color = AppTheme.gold

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(AppTheme.separator.opacity(0.7))
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.75), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("进度")
        .accessibilityValue("\(Int(clamped * 100))%")
    }

    private var clamped: Double {
        min(max(progress, 0), 1)
    }
}

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 7

    @State private var animated = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.separator.opacity(0.65), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: animated ? clamped : 0)
                .stroke(
                    AngularGradient(
                        colors: [AppTheme.gold, AppTheme.accent, AppTheme.goldBright, AppTheme.gold],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.15)) {
                animated = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel("今日进度")
        .accessibilityValue("\(Int(clamped * 100))%")
    }

    private var clamped: Double {
        min(max(progress, 0), 1)
    }
}

// MARK: - StatTile

struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    var unit: String?
    var footnote: String?
    var tint: Color = AppTheme.gold

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Eyebrow(text: label, tint: AppTheme.textTertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
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
                .strokeBorder(AppTheme.separator.opacity(0.72), lineWidth: 0.8)
        )
    }
}

// MARK: - EmptyState

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppTheme.goldSoft.opacity(0.8))
                    .frame(width: 46, height: 46)
                Circle()
                    .strokeBorder(AppTheme.gold.opacity(0.30), lineWidth: 0.8)
                    .frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.gold)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

// MARK: - QuickActionButton

struct QuickActionButton: View {
    let icon: String
    let title: String
    var tint: Color = AppTheme.gold
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.10))
                    Circle()
                        .strokeBorder(tint.opacity(0.34), lineWidth: 0.8)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 46, height: 46)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle())
    }
}

// MARK: - ModulePlaceholderView

/// 尚未开发模块的统一页面：展示阶段规划，不展示任何演示数据。
struct ModulePlaceholderView: View {
    let icon: String
    let title: String
    let phase: String
    let summary: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            header
            planCard
            Text("当前阶段仅展示规划，未接入真实数据。")
                .font(.system(size: 10))
                .tracking(0.4)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    PillBadge(text: phase)
                    Spacer()
                    Eyebrow(text: "LifeOS Module", tint: AppTheme.textTertiary)
                }

                ZStack {
                    Circle()
                        .fill(AppTheme.goldSoft.opacity(0.75))
                        .frame(width: 70, height: 70)
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [AppTheme.gold.opacity(0.55), AppTheme.accent.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .frame(width: 70, height: 70)
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(AppTheme.gold)
                }

                Text(title)
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
    }

    private var planCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Eyebrow(text: "Planned Features")
                    Spacer()
                    Text("规划中")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Hairline()

                ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 13) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(AppTheme.gold)
                            .padding(.top, 3)

                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Hairline()

                Text("完成后此页面会替换为真实可用的功能界面。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }
}
