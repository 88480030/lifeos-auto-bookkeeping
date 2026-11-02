import AppIntents

/// LiveActivityIntent executes in the app process; the app owns persistence and
/// the state machine. The extension only needs the same discoverable intent type.
struct ToggleStudyActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "暂停或继续专注" }
    static var description: IntentDescription { "同步 LifeOS 番茄钟和实时活动的状态。" }
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "计时标识") var timerID: String
    @Parameter(title: "继续计时") var resume: Bool
    @Parameter(title: "阶段") var phase: String

    init() {}

    init(timerID: String, resume: Bool, phase: String) {
        self.timerID = timerID
        self.resume = resume
        self.phase = phase
    }

    func perform() async throws -> some IntentResult {
        #if !LIFEOS_WIDGET
        try await StudyTimerEngine.shared.performActivityAction(timerID: timerID, phase: phase, resume: resume)
        #endif
        return .result()
    }
}
