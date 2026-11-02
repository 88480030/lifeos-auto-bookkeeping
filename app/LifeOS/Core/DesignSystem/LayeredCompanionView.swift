import SwiftUI

private struct LifeOSSurfaceVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

private struct LifeOSViewportRectKey: EnvironmentKey {
    static let defaultValue = CGRect.zero
}

extension EnvironmentValues {
    /// Pause character animation in mounted but hidden tab roots.
    var lifeOSSurfaceVisible: Bool {
        get { self[LifeOSSurfaceVisibleKey.self] }
        set { self[LifeOSSurfaceVisibleKey.self] = newValue }
    }

    /// The actual app viewport, measured once by the root in global coordinates.
    var lifeOSViewportRect: CGRect {
        get { self[LifeOSViewportRectKey.self] }
        set { self[LifeOSViewportRectKey.self] = newValue }
    }
}

/// One original illustration animates as a single stable layer.
struct LayeredCompanionView: View {
    let character: CompanionCharacter
    var mood: CompanionMood = .ready
    var reactionTrigger: Int = 0
    var onReact: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.lifeOSSurfaceVisible) private var surfaceVisible
    @State private var mounted = false
    @State private var inViewport = true
    @State private var motionEpoch = Date()
    @State private var reactionStartedAt: Date?
    @State private var reactionCarry = CompanionReactionDelta()
    @State private var previousMood: CompanionMood?
    @State private var moodChangedAt: Date?

    private var canAnimate: Bool {
        mounted && inViewport && surfaceVisible && scenePhase == .active && !reduceMotion
    }

    var body: some View {
        Button {
            Haptics.tap()
            beginReaction()
            onReact?()
        } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !canAnimate)) { timeline in
                GeometryReader { geometry in
                    let side = min(geometry.size.width, geometry.size.height)
                    let pose = pose(at: timeline.date)
                    assembledRig(pose: pose, side: side)
                        .frame(width: side, height: side)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("companion.\(character.rawValue)")
        .accessibilityLabel("\(character.name)，互动角色")
        .accessibilityValue(mood.description)
        .accessibilityHint("轻点，让伙伴轻轻回应")
        .onAppear { mounted = true }
        .onDisappear { mounted = false }
        .onChange(of: mood) { oldMood, _ in
            previousMood = oldMood
            moodChangedAt = .now
            beginReaction()
        }
        .onChange(of: reactionTrigger) { _, _ in
            beginReaction()
        }
        .modifier(CompanionViewportObserver(isVisible: $inViewport))
    }

    private func assembledRig(pose: CompanionPose, side: CGFloat) -> some View {
        Image(character == .anya ? "MascotOtter" : "MascotFox")
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .scaleEffect(x: 1, y: pose.bodyScaleY, anchor: .bottom)
            .offset(y: side * (pose.bodyLift + pose.headNod * 0.35) / 512)
            .accessibilityHidden(true)
    }

    private func pose(at date: Date) -> CompanionPose {
        guard canAnimate else { return CompanionPose.settled(mood, character: character) }
        let time = max(0, date.timeIntervalSince(motionEpoch))
        var result = CompanionPose.idle(mood, character: character, time: time)
        if let previousMood, let moodChangedAt {
            let progress = min(1, max(0, date.timeIntervalSince(moodChangedAt) / 0.36))
            let smooth = progress * progress * (3 - 2 * progress)
            let previous = CompanionPose.idle(previousMood, character: character, time: time)
            result = previous.interpolated(to: result, progress: smooth)
        }
        let reaction = reactionDisplacement(at: date)
        result.headAngle += reaction.headAngle
        result.headNod += reaction.headNod
        result.armAngle += reaction.armAngle
        result.armAngle = min(9, max(-9, result.armAngle))
        return result
    }

    private func beginReaction() {
        let now = Date()
        reactionCarry = reactionDisplacement(at: now)
        reactionStartedAt = now
    }

    private func reactionDisplacement(at date: Date) -> CompanionReactionDelta {
        guard let reactionStartedAt else { return CompanionReactionDelta() }
        let elapsed = date.timeIntervalSince(reactionStartedAt)
        return CompanionReactionDelta.sample(elapsed: elapsed, character: character, carry: reactionCarry)
    }

}

private struct CompanionFramePreference: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct CompanionViewportObserver: ViewModifier {
    @Binding var isVisible: Bool
    @Environment(\.lifeOSViewportRect) private var viewport
    @State private var characterFrame = CGRect.zero

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollVisibilityChange(threshold: 0.1) { isVisible = $0 }
        } else {
            content
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: CompanionFramePreference.self,
                            value: geometry.frame(in: .global)
                        )
                    }
                }
                .onPreferenceChange(CompanionFramePreference.self) { frame in
                    characterFrame = frame
                    updateVisibility(frame: frame, viewport: viewport)
                }
                .onChange(of: viewport) { _, viewport in
                    updateVisibility(frame: characterFrame, viewport: viewport)
                }
        }
    }

    private func updateVisibility(frame: CGRect, viewport: CGRect) {
        // Previews without a root measurement retain the scene/tab gate.
        guard !viewport.isEmpty else { isVisible = true; return }
        guard !frame.isEmpty else { isVisible = false; return }
        let intersection = frame.intersection(viewport)
        let visibleArea = intersection.isNull ? 0 : intersection.width * intersection.height
        isVisible = visibleArea / (frame.width * frame.height) >= 0.1
    }
}
