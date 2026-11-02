import SwiftUI

/// Completion feedback for task buttons. The enclosing button owns its label
/// and hit target; this mark never starts an entrance or a repeating animation.
struct CompletionToggleMark: View {
    let isCompleted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var completionRevision = 0

    var body: some View {
        let animateCompletion = isCompleted && !reduceMotion
        ZStack {
            Circle()
                .fill(isCompleted ? ArchiveTheme.mintDeep : .clear)
            Circle()
                .strokeBorder(
                    isCompleted ? ArchiveTheme.mintDeep : ArchiveTheme.inkSoft,
                    lineWidth: 1.8
                )
            CompletionCheckmark()
                .trim(from: 0, to: reduceMotion ? 1 : (isCompleted ? 1 : 0))
                .stroke(
                    ArchiveTheme.paper,
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                )
                .opacity(isCompleted ? 1 : 0)
                .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.22), value: isCompleted)
        }
        .frame(width: 24, height: 24)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.18), value: isCompleted)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: completionRevision) { content, scale in
            content.scaleEffect(animateCompletion ? scale : 1)
        } keyframes: { _ in
            CubicKeyframe(1.13, duration: 0.08)
            CubicKeyframe(1, duration: 0.20)
        }
        .onChange(of: isCompleted) { wasCompleted, completed in
            guard completed && !wasCompleted && !reduceMotion else { return }
            completionRevision += 1
        }
        .accessibilityHidden(true)
    }
}

private struct CompletionCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.26, y: rect.height * 0.51))
        path.addLine(to: CGPoint(x: rect.width * 0.43, y: rect.height * 0.68))
        path.addLine(to: CGPoint(x: rect.width * 0.75, y: rect.height * 0.34))
        return path
    }
}
