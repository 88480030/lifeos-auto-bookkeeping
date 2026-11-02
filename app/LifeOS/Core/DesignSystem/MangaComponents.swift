import SwiftUI

// MARK: - Expressions

enum MiraExpression: String, CaseIterable {
    case neutral
    case happy
    case alert
    case focus
    case thinking

    var assetName: String {
        "MascotFox"
    }

    var accessibilityLabel: String {
        switch self {
        case .neutral: "情报官角色，日常表情"
        case .happy: "情报官角色，开心表情"
        case .alert: "情报官角色，紧急提醒表情"
        case .focus: "情报官角色，专注表情"
        case .thinking: "情报官角色，思考表情"
        }
    }
}

// MARK: - Panel

/// 漫画分镜面板：粗墨线、纸张表面、硬阴影。
struct MangaPanel<Content: View>: View {
    var fill: Color = ArchiveTheme.paperRaised
    var borderWidth: CGFloat = 2.4
    var cornerRadius: CGFloat = 12
    var padding: CGFloat = 16
    var hardShadow: Bool = true
    var rotation: Double = 0

    private let content: Content

    init(
        fill: Color = ArchiveTheme.paperRaised,
        borderWidth: CGFloat = 2.4,
        cornerRadius: CGFloat = 12,
        padding: CGFloat = 16,
        hardShadow: Bool = true,
        rotation: Double = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.fill = fill
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.hardShadow = hardShadow
        self.rotation = rotation
        self.content = content()
    }

    var body: some View {
        ZStack {
            if hardShadow {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ArchiveTheme.ink)
                    .offset(x: 4, y: 5)
            }

            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(ArchiveTheme.ink, lineWidth: borderWidth)
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        }
        .rotationEffect(.degrees(rotation))
        .padding(.trailing, hardShadow ? 4 : 0)
        .padding(.bottom, hardShadow ? 5 : 0)
    }
}

// MARK: - Screentone / speed lines

struct MangaHalftone: View {
    var color: Color = ArchiveTheme.ink
    var opacity: Double = 0.12
    var spacing: CGFloat = 11

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : spacing / 2
                while x < size.width {
                    let radius: CGFloat = (row + Int(x / spacing)) % 4 == 0 ? 1.25 : 0.7
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                        with: .color(color.opacity(opacity))
                    )
                    x += spacing
                }
                y += spacing
                row += 1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MangaSpeedLines: View {
    var color: Color = ArchiveTheme.ink
    var opacity: Double = 0.09
    var count: Int = 46

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.88, y: size.height * 0.22)
            let outer = max(size.width, size.height) * 1.4
            let inner = min(size.width, size.height) * 0.16

            for index in 0..<count {
                let angle = (Double(index) / Double(count)) * Double.pi * 2 + 0.17
                let startRadius = inner + CGFloat(index % 5) * 4
                let endRadius = outer - CGFloat(index % 7) * 12
                let start = CGPoint(
                    x: center.x + cos(angle) * startRadius,
                    y: center.y + sin(angle) * startRadius
                )
                let end = CGPoint(
                    x: center.x + cos(angle) * endRadius,
                    y: center.y + sin(angle) * endRadius
                )
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(
                    path,
                    with: .color(color.opacity(opacity)),
                    lineWidth: index % 6 == 0 ? 1.6 : 0.8
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Caption / section heading

struct MangaCaptionTag: View {
    let text: String
    var fill: Color = ArchiveTheme.ink
    var textColor: Color = ArchiveTheme.paperRaised
    var rotation: Double = -1.2

    var body: some View {
        Text(text.uppercased())
            .font(.archiveMonoStrong)
            .tracking(0.9)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(fill)
            .rotationEffect(.degrees(rotation))
            .accessibilityHidden(true)
    }
}

struct MangaSectionHeading: View {
    let code: String
    let title: String
    var trailing: String?
    var accent: Color = ArchiveTheme.mintDeep

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                MangaCaptionTag(text: code, fill: accent, textColor: ArchiveTheme.ink)
                if let trailing {
                    Text(trailing.uppercased())
                        .font(.archiveMono)
                        .tracking(0.7)
                        .foregroundStyle(ArchiveTheme.inkMuted)
                }
            }

            Text(title)
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundStyle(ArchiveTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Speech bubble

struct MangaSpeechBubble: View {
    let text: String
    var footnote: String?
    var fill: Color = ArchiveTheme.paperRaised
    var textColor: Color = ArchiveTheme.ink
    var borderColor: Color = ArchiveTheme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(textColor)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if let footnote {
                Text(footnote.uppercased())
                    .font(.archiveMono)
                    .tracking(0.6)
                    .foregroundStyle(textColor.opacity(0.55))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            MangaBubbleShape()
                .fill(fill)
        )
        .overlay(
            MangaBubbleShape()
                .stroke(borderColor, lineWidth: 2.2)
        )
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct MangaBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let body = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: max(0, rect.height - 10)
        )

        var path = Path(roundedRect: body, cornerRadius: 8, style: .continuous)
        path.move(to: CGPoint(x: body.minX + 24, y: body.maxY - 1))
        path.addLine(to: CGPoint(x: body.minX + 16, y: rect.maxY))
        path.addLine(to: CGPoint(x: body.minX + 40, y: body.maxY - 1))
        path.closeSubpath()
        return path
    }
}

// MARK: - Character

struct MangaCharacterImage: View {
    let expression: MiraExpression
    var width: CGFloat
    var height: CGFloat

    @ObservedObject private var artwork = MiraArtStore.shared

    var body: some View {
        Group {
            if let customImage = artwork.customImage {
                Image(uiImage: customImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(ArchiveTheme.ink.opacity(0.35), lineWidth: 1)
                    )
            } else {
                Image(expression.assetName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(artwork.customImage == nil ? expression.accessibilityLabel : "自定义情报官立绘")
        .accessibilityHint(artwork.customImage == nil ? "原创角色占位插画，正式插画尚未替换" : "来自本机相册的自定义立绘")
    }
}

// MARK: - Decorative

struct MangaStar: View {
    var tint: Color = ArchiveTheme.gold
    var size: CGFloat = 12

    var body: some View {
        MangaStarShape()
            .fill(tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct MangaStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let points = 4
        for index in 0..<(points * 2) {
            let radius = index.isMultiple(of: 2) ? rect.width / 2 : rect.width / 7
            let angle = -Double.pi / 2 + Double(index) * Double.pi / Double(points)
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

struct MangaSoundEffect: View {
    let text: String
    var tint: Color = ArchiveTheme.coral
    var angle: Double = -7

    var body: some View {
        Text(text)
            .font(.system(size: 18, weight: .black, design: .rounded))
            .italic()
            .foregroundStyle(tint)
            .shadow(color: ArchiveTheme.ink, radius: 0, x: 1.4, y: 1.4)
            .rotationEffect(.degrees(angle))
            .accessibilityHidden(true)
    }
}

// MARK: - Mission row

struct MangaMissionRow: View {
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
            HStack(spacing: 10) {
                MangaCaptionTag(text: code, fill: tint, textColor: ArchiveTheme.ink)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(ArchiveTheme.ink)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.archiveCaption)
                        .foregroundStyle(ArchiveTheme.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 4)

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

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(ArchiveTheme.ink)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(ArchivePressStyle())
        .accessibilityLabel("\(title)，\(subtitle)，\(metric)")
        .accessibilityHint("打开\(title)")
    }
}

// MARK: - Tool button

struct MangaToolButton: View {
    let icon: String
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(ArchiveTheme.paperRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(ArchiveTheme.ink, lineWidth: 1.4)
                    )

                Text(title)
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(ArchiveTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(ArchivePressStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - Page shell

struct MangaPageHeader<Accessory: View>: View {
    let code: String
    let title: String
    let subtitle: String
    let expression: MiraExpression

    private let accessory: Accessory

    init(
        code: String,
        title: String,
        subtitle: String,
        expression: MiraExpression,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.code = code
        self.title = title
        self.subtitle = subtitle
        self.expression = expression
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                MangaCaptionTag(
                    text: code,
                    fill: ArchiveTheme.ink,
                    rotation: -1.5
                )

                Text(title)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(ArchiveTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(subtitle)
                    .font(.archiveMono)
                    .foregroundStyle(ArchiveTheme.inkSoft)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 7) {
                MangaCharacterImage(expression: expression, width: 56, height: 72)
                accessory
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ArchiveTheme.sageWash)
                .shadow(color: Color.black.opacity(0.10), radius: 0, x: 3, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ArchiveTheme.ink, lineWidth: 2)
        )
    }
}

struct MangaPageFooter: View {
    let page: String

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(ArchiveTheme.ink.opacity(0.22))
                    .frame(height: 1)
                Text("TO BE CONTINUED")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(ArchiveTheme.ink)
                    .fixedSize()
                Rectangle()
                    .fill(ArchiveTheme.ink.opacity(0.22))
                    .frame(height: 1)
            }

            Text("LIFEOS · CLASSIFIED  /  PAGE \(page)  /  YOUR EYES ONLY")
                .font(.archiveMono)
                .tracking(0.6)
                .foregroundStyle(ArchiveTheme.inkMuted)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("LifeOS 机密档案，第 \(page) 页")
    }
}


struct MangaGingham: View {
    var color: Color = ArchiveTheme.coral
    var opacity: Double = 0.08
    var cell: CGFloat = 22

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let isTint = (Int(x / cell) + Int(y / cell)).isMultiple(of: 2)
                    context.fill(
                        Path(CGRect(x: x, y: y, width: cell, height: cell)),
                        with: .color(color.opacity(isTint ? opacity : opacity * 0.45))
                    )
                    x += cell
                }
                y += cell
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
