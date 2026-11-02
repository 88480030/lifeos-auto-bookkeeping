import SwiftUI

// MARK: - Tomato mascot

enum TomatoMood {
    case idle
    case running
    case paused
    case rest

    var line: String {
        switch self {
        case .idle: "准备好了吗？先选个小任务。"
        case .running: "一起专注，别偷看手机。"
        case .paused: "先喘口气，我等你。"
        case .rest: "休息一下，喝口水。"
        }
    }
}

struct TomatoMascot: View {
    var mood: TomatoMood

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blink = false

    private let tomato = Color(hex: 0xE96A5E)
    private let tomatoDark = Color(hex: 0xC84E48)
    private let leaf = Color(hex: 0x5E946F)

    var body: some View {
        ZStack {
            // body
            Ellipse()
                .fill(tomato)
                .frame(width: 58, height: 50)
                .overlay(
                    Ellipse()
                        .strokeBorder(ArchiveTheme.ink, lineWidth: 2.2)
                )
                .offset(y: 6)

            // highlight
            Ellipse()
                .fill(Color.white.opacity(0.32))
                .frame(width: 13, height: 8)
                .rotationEffect(.degrees(-24))
                .offset(x: -16, y: -8)

            // leaves
            TomatoLeaf()
                .fill(leaf)
                .frame(width: 34, height: 18)
                .overlay(TomatoLeaf().stroke(ArchiveTheme.ink, lineWidth: 1.8))
                .offset(y: -21)

            // face
            VStack(spacing: 3) {
                HStack(spacing: 10) {
                    eye(left: true)
                    eye(left: false)
                }

                mouth
            }
            .offset(y: 10)

            HStack(spacing: 1) {
                Capsule().fill(tomatoDark).frame(width: 10, height: 2.5)
                Capsule().fill(tomatoDark).frame(width: 10, height: 2.5)
            }
            .offset(x: -24, y: 22)

            HStack(spacing: 1) {
                Capsule().fill(tomatoDark).frame(width: 10, height: 2.5)
                Capsule().fill(tomatoDark).frame(width: 10, height: 2.5)
            }
            .offset(x: 24, y: 22)
        }
        .frame(width: 72, height: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("番茄钟小助手，\(mood.line)")
        .task(id: reduceMotion) {
            blink = false
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.1))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.16)) { blink = true }
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.easeInOut(duration: 0.16)) { blink = false }
            }
        }
    }

    @ViewBuilder
    private func eye(left: Bool) -> some View {
        if mood == .paused || blink {
            Capsule()
                .fill(ArchiveTheme.ink)
                .frame(width: 13, height: 2.5)
                .offset(y: left ? 0 : 0)
        } else {
            ZStack {
                Circle()
                    .fill(ArchiveTheme.ink)
                    .frame(width: 9, height: 10)
                Circle()
                    .fill(Color.white)
                    .frame(width: 3, height: 3)
                    .offset(x: -2, y: -2)
            }
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .running:
            Circle()
                .fill(ArchiveTheme.ink)
                .frame(width: 7, height: 7)
        case .rest:
            Capsule()
                .fill(ArchiveTheme.ink)
                .frame(width: 11, height: 2.2)
        case .paused:
            Capsule()
                .fill(ArchiveTheme.ink)
                .frame(width: 8, height: 2.2)
        case .idle:
            SmileShape()
                .stroke(ArchiveTheme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 15, height: 7)
        }
    }
}

private struct TomatoLeaf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let leaves = 5
        for index in 0..<leaves {
            let angle = -Double.pi + Double(index) * Double.pi / Double(leaves - 1)
            let tip = CGPoint(
                x: center.x + cos(angle) * rect.width * 0.48,
                y: center.y + sin(angle) * rect.height * 0.85
            )
            path.move(to: CGPoint(x: center.x, y: center.y))
            path.addQuadCurve(
                to: tip,
                control: CGPoint(
                    x: center.x + cos(angle) * rect.width * 0.22,
                    y: center.y + sin(angle) * rect.height * 0.25
                )
            )
            path.addQuadCurve(
                to: CGPoint(x: center.x, y: center.y),
                control: CGPoint(
                    x: center.x + cos(angle) * rect.width * 0.36,
                    y: center.y + sin(angle) * rect.height * 0.60
                )
            )
        }
        return path
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.8)
        )
        return path
    }
}

// MARK: - Cute ring

struct CutePomodoroRing: View {
    let progress: Double
    let tint: Color

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ArchiveTheme.rule.opacity(0.55), lineWidth: 12)

            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(ArchiveTheme.ink.opacity(0.10))
                    .frame(width: 2, height: 6)
                    .offset(y: -105)
                    .rotationEffect(.degrees(Double(index) * 30))
            }

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.65), tint, ArchiveTheme.gold, tint],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .accessibilityElement()
        .accessibilityLabel("番茄钟进度")
        .accessibilityValue("\(Int(clamped * 100))%")
    }
}

// MARK: - Speech

struct CutePomodoroBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(ArchiveTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(ArchiveTheme.paperRaised)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(ArchiveTheme.ink.opacity(0.75), lineWidth: 1.2)
            )
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(ArchiveTheme.paperRaised)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(ArchiveTheme.ink.opacity(0.75), lineWidth: 1))
                    .offset(x: 15, y: 7)
            }
            .accessibilityLabel(text)
    }
}

struct TomatoDot: View {
    let filled: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(filled ? Color(hex: 0xE96A5E) : ArchiveTheme.rule.opacity(0.7))
                .frame(width: 11, height: 11)
            if filled {
                TomatoLeaf()
                    .fill(Color(hex: 0x5E946F))
                    .frame(width: 8, height: 4)
                    .offset(y: -6)
            }
        }
        .frame(width: 14, height: 14)
    }
}
