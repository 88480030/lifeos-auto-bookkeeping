import SwiftUI

// MARK: - Background

struct ArchiveBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            ArchiveTheme.paper

            if !reduceTransparency {
                ArchivePaperGrain()
                    .opacity(colorScheme == .dark ? 0.20 : 0.36)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// 静态纸纹：低对比、缓存式 Canvas，不逐帧生成。
private struct ArchivePaperGrain: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 17
            var row = 0
            var y: CGFloat = 4

            while y < size.height {
                var column = 0
                var x: CGFloat = 5
                while x < size.width {
                    let diameter: CGFloat = (row + column) % 5 == 0 ? 0.85 : 0.55
                    let opacity: Double = (row + column) % 7 == 0 ? 0.035 : 0.018
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                        with: .color(ArchiveTheme.ink.opacity(opacity))
                    )
                    x += step
                    column += 1
                }
                y += step
                row += 1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - File tab / sheet

struct ArchiveFileTab: View {
    let title: String
    var code: String?

    var body: some View {
        HStack(spacing: 7) {
            if let code {
                Text(code.uppercased())
                    .font(.archiveMonoStrong)
                    .foregroundStyle(ArchiveTheme.gold)
            }

            Text(title.uppercased())
                .font(.archiveMonoStrong)
                .foregroundStyle(ArchiveTheme.inkSoft)
                .lineLimit(1)
        }
        .tracking(0.9)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: ArchiveTheme.tabRadius, style: .continuous)
                .fill(ArchiveTheme.paperTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveTheme.tabRadius, style: .continuous)
                .strokeBorder(ArchiveTheme.rule, lineWidth: 0.9)
        )
        .accessibilityHidden(true)
    }
}

struct ArchiveDossierSheet<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let tabTitle: String
    var code: String?
    var stamp: String?
    var padding: CGFloat
    private let content: Content

    init(
        tabTitle: String,
        code: String? = nil,
        stamp: String? = nil,
        padding: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.tabTitle = tabTitle
        self.code = code
        self.stamp = stamp
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: -8) {
            ArchiveFileTab(title: tabTitle, code: code)
                .padding(.leading, 8)
                .zIndex(1)

            ZStack(alignment: .topTrailing) {
                content
                    .padding(padding)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: ArchiveTheme.sheetRadius, style: .continuous)
                            .fill(ArchiveTheme.paperRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ArchiveTheme.sheetRadius, style: .continuous)
                            .strokeBorder(ArchiveTheme.rule.opacity(0.9), lineWidth: 1)
                    )
                    .shadow(
                        color: ArchiveTheme.paperShadow(for: colorScheme),
                        radius: 14,
                        x: 0,
                        y: 8
                    )

                if let stamp {
                    ArchiveStamp(text: stamp)
                        .padding(.top, 14)
                        .padding(.trailing, 14)
                }
            }
        }
    }
}

// MARK: - Stamp

struct ArchiveStamp: View {
    let text: String
    var tint: Color = ArchiveTheme.stamp
    var angle: Double = -4

    var body: some View {
        Text(text.uppercased())
            .font(.archiveMonoStrong)
            .tracking(1.1)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        tint.opacity(0.70),
                        style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                    )
            )
            .rotationEffect(.degrees(angle))
            .opacity(0.82)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Speech bubble

struct ArchiveSpeechBubble: View {
    let text: String
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.archiveBody)
                .foregroundStyle(ArchiveTheme.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if let footnote {
                Text(footnote.uppercased())
                    .font(.archiveMono)
                    .tracking(0.7)
                    .foregroundStyle(ArchiveTheme.inkMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            ArchiveSpeechBubbleShape()
                .fill(ArchiveTheme.paperRaised)
        )
        .overlay(
            ArchiveSpeechBubbleShape()
                .stroke(ArchiveTheme.rule, lineWidth: 1)
        )
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct ArchiveSpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let body = CGRect(
            x: rect.minX,
            y: rect.minY + 12,
            width: rect.width,
            height: max(0, rect.height - 12)
        )

        var path = Path(
            roundedRect: body,
            cornerRadius: 16,
            style: .continuous
        )

        path.move(to: CGPoint(x: body.maxX - 62, y: body.minY + 1))
        path.addLine(to: CGPoint(x: body.maxX - 38, y: rect.minY))
        path.addLine(to: CGPoint(x: body.maxX - 24, y: body.minY + 1))
        path.closeSubpath()

        return path
    }
}

// MARK: - Progress

struct ArchiveProgressRing: View {
    let progress: Double
    var tint: Color = ArchiveTheme.mintDeep
    var lineWidth: CGFloat = 7

    private var clamped: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ArchiveTheme.rule.opacity(0.8), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .accessibilityElement()
        .accessibilityLabel("今日行动完成度")
        .accessibilityValue("\(Int(clamped * 100))%")
    }
}

// MARK: - Section header

struct ArchiveSectionHeader: View {
    let title: String
    let eyebrow: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(.archiveMonoStrong)
                    .tracking(1.1)
                    .foregroundStyle(ArchiveTheme.gold)
                Text(title)
                    .font(.archiveSection)
                    .foregroundStyle(ArchiveTheme.ink)
            }

            Spacer(minLength: 8)

            if let trailing {
                Text(trailing.uppercased())
                    .font(.archiveMono)
                    .tracking(0.7)
                    .foregroundStyle(ArchiveTheme.inkMuted)
            }
        }
    }
}

// MARK: - Rules

struct ArchiveDashedRule: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: proxy.size.width, y: 0.5))
            }
            .stroke(
                ArchiveTheme.rule.opacity(0.9),
                style: StrokeStyle(lineWidth: 0.8, dash: [4, 4])
            )
        }
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}

// MARK: - Metric

struct ArchiveMetricView: View {
    let label: String
    let value: String
    var unit: String?
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.archiveMono)
                .tracking(0.7)
                .foregroundStyle(ArchiveTheme.inkMuted)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ArchiveTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                if let unit {
                    Text(unit)
                        .font(.archiveMono)
                        .foregroundStyle(ArchiveTheme.inkMuted)
                }
            }

            if let footnote {
                Text(footnote)
                    .font(.archiveMono)
                    .foregroundStyle(ArchiveTheme.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Mission row

struct MissionIndexRow: View {
    let code: String
    let title: String
    let subtitle: String
    let metric: String
    let status: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                VStack(spacing: 5) {
                    Text(code)
                        .font(.archiveMonoStrong)
                        .foregroundStyle(tint)
                    Rectangle()
                        .fill(tint.opacity(0.55))
                        .frame(width: 18, height: 2)
                }
                .frame(width: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.archiveSection)
                        .foregroundStyle(ArchiveTheme.ink)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.archiveCaption)
                        .foregroundStyle(ArchiveTheme.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(metric)
                        .font(.system(.headline, design: .serif).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(ArchiveTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(status.uppercased())
                        .font(.archiveMono)
                        .tracking(0.5)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ArchiveTheme.inkMuted.opacity(0.65))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(ArchivePressStyle())
        .accessibilityLabel("\(title)，\(subtitle)，\(metric)")
        .accessibilityHint("打开\(title)")
    }
}

// MARK: - Field kit

struct ArchiveFieldKitButton: View {
    let icon: String
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint.opacity(0.09))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(tint.opacity(0.28), lineWidth: 0.8)
                    )

                Text(title)
                    .font(.system(.caption2, weight: .medium))
                    .foregroundStyle(ArchiveTheme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(ArchivePressStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - Character

struct MiraPortraitCard: View {
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Image("MascotFox")
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 34 : 72, height: compact ? 34 : 82)
                .background(
                    RoundedRectangle(cornerRadius: compact ? 8 : 12, style: .continuous)
                        .fill(ArchiveTheme.paperRaised)
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: compact ? 8 : 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 8 : 12, style: .continuous)
                        .strokeBorder(ArchiveTheme.rule.opacity(0.9), lineWidth: 0.9)
                )

            if !compact {
                Text("MIRA / 07")
                    .font(.archiveMono)
                    .tracking(0.6)
                    .foregroundStyle(ArchiveTheme.inkMuted)

                Text("PLACEHOLDER")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(ArchiveTheme.inkMuted.opacity(0.8))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("原创情报官 MIRA 的占位插画")
        .accessibilityHint("正式角色插画尚未替换")
    }
}

// MARK: - Empty state

struct ArchiveEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(ArchiveTheme.inkMuted)

            Text(title)
                .font(.archiveSection)
                .foregroundStyle(ArchiveTheme.ink)

            Text(message)
                .font(.archiveCaption)
                .foregroundStyle(ArchiveTheme.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - Press style

struct ArchivePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.80),
                value: configuration.isPressed
            )
    }
}
