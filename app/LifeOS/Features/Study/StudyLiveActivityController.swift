@preconcurrency import ActivityKit
import Combine
import Foundation

/// Owns one activity for the entire focus → break run. Date-driven text is rendered
/// by iOS; this queue sends only real state transitions and serializes mutations.
@MainActor
final class StudyLiveActivityController: ObservableObject {
    static let shared = StudyLiveActivityController()
    @Published private(set) var isEnabled: Bool
    @Published private(set) var systemAllowsActivities = false
    @Published private(set) var statusMessage = "开始专注后，在灵动岛和锁屏查看倒计时。"

    private let defaults: UserDefaults
    private let preferenceKey = "lifeos.study.liveActivity.enabled"
    private let presentedKey = "lifeos.study.liveActivity.presentedID"
    private var pending: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: preferenceKey) as? Bool ?? true
        refreshAuthorization()
    }

    func refreshAuthorization() {
        systemAllowsActivities = ActivityAuthorizationInfo().areActivitiesEnabled
        if !isEnabled {
            statusMessage = "实时活动已关闭，应用内计时继续可用。"
        } else if !systemAllowsActivities {
            statusMessage = "系统未允许实时活动，可在 LifeOS 的系统设置中开启。"
        }
    }

    func setEnabled(_ value: Bool) {
        isEnabled = value
        defaults.set(value, forKey: preferenceKey)
        refreshAuthorization()
    }

    @discardableResult
    func synchronize(_ snapshot: PomodoroActivitySnapshot?, allowStart: Bool, force: Bool = false) -> Task<Void, Never> {
        let previous = pending
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            await apply(snapshot, allowStart: allowStart, force: force)
        }
        pending = task
        return task
    }

    func waitForUpdates() async { await pending?.value }

    private func apply(_ snapshot: PomodoroActivitySnapshot?, allowStart: Bool, force: Bool) async {
        refreshAuthorization()
        let active = Activity<StudyActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        guard isEnabled, systemAllowsActivities, let snapshot else {
            for activity in active { await activity.end(nil, dismissalPolicy: .immediate) }
            if snapshot == nil {
                defaults.removeObject(forKey: presentedKey)
                if isEnabled && systemAllowsActivities {
                    statusMessage = "开始专注后，在灵动岛和锁屏查看倒计时。"
                }
            }
            return
        }

        let state = StudyActivityAttributes.ContentState(
            phase: snapshot.phase, phaseTitle: snapshot.phaseTitle, taskTitle: snapshot.taskTitle,
            isPaused: snapshot.isPaused, remainingSeconds: snapshot.remainingSeconds,
            durationSeconds: snapshot.durationSeconds, startAt: snapshot.startAt, endAt: snapshot.endAt,
            round: snapshot.round, rounds: snapshot.rounds
        )
        let content = ActivityContent(state: state, staleDate: snapshot.isPaused ? nil : snapshot.endAt)
        let existing = active.first { $0.attributes.timerID == snapshot.timerID }
        for obsolete in active where obsolete.id != existing?.id {
            await obsolete.end(nil, dismissalPolicy: .immediate)
        }
        if let existing {
            if existing.content.state != state { await existing.update(content) }
            statusMessage = snapshot.isPaused ? "灵动岛与锁屏已暂停。" : "灵动岛与锁屏正在显示本轮倒计时。"
            return
        }

        guard allowStart else { return }
        // A swipe-away is a user choice. An explicit retry or new run can show it again.
        if !force && defaults.string(forKey: presentedKey) == snapshot.timerID {
            statusMessage = "本轮实时活动已收起，可点击重新显示。"
            return
        }
        do {
            _ = try Activity.request(attributes: StudyActivityAttributes(timerID: snapshot.timerID),
                                     content: content, pushType: nil)
            defaults.set(snapshot.timerID, forKey: presentedKey)
            statusMessage = snapshot.isPaused ? "灵动岛与锁屏已暂停。" : "灵动岛与锁屏正在显示本轮倒计时。"
        } catch {
            statusMessage = "实时活动暂时未能显示，应用内计时不受影响，可稍后重试。"
        }
    }
}
