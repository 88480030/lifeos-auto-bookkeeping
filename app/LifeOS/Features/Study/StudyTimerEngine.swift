import Combine
import Foundation
import SwiftData
import UIKit
import UserNotifications

// MARK: - Preferences

struct StudyPreferences: Codable, Equatable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var longBreakEvery = 4
    var dailyGoalMinutes = 60

    var configuration: PomodoroConfiguration {
        PomodoroConfiguration(
            focusMinutes: focusMinutes,
            shortBreakMinutes: shortBreakMinutes,
            longBreakMinutes: longBreakMinutes,
            longBreakEvery: longBreakEvery
        )
    }
}

// MARK: - Engine

@MainActor
final class StudyTimerEngine: ObservableObject {
    static let shared = StudyTimerEngine()
    @Published private(set) var machine: PomodoroMachine
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var preferences: StudyPreferences
    @Published private(set) var notificationDenied = false
    @Published private(set) var statusMessage: String?

    private let defaults: UserDefaults
    private let machineKey = "lifeos.study.pomodoro.machine.v1"
    private let preferencesKey = "lifeos.study.preferences.v1"
    private let notificationID = "lifeos.study.pomodoro.timer"
    private let activityTimerKey = "lifeos.study.liveActivity.timerID"
    private let notificationCenter = UNUserNotificationCenter.current()

    private var context: ModelContext?
    private var statusClearTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var notificationGeneration = UUID()
    private var activityContainer: ModelContainer?
    private let liveActivity = StudyLiveActivityController.shared

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let prefs = Self.loadPreferences(defaults: defaults)
        self.preferences = prefs
        let loadedMachine = Self.loadMachine(defaults: defaults)
            ?? PomodoroMachine(configuration: prefs.configuration)
        self.machine = loadedMachine
        self.remainingSeconds = loadedMachine.remainingSeconds(now: .now)
    }

    var isIdle: Bool { machine.isIdle }
    var isRunning: Bool { machine.isRunning }
    var isPaused: Bool { machine.isPaused }
    var phase: PomodoroPhase { machine.phase }
    var cycleIndex: Int { machine.cycleIndex }
    var longBreakEvery: Int { machine.configuration.longBreakEvery }
    var phaseDurationSeconds: Int { machine.phaseDurationSeconds }
    var progress: Double { machine.progress(now: .now) }

    // MARK: Lifecycle

    func attach(context: ModelContext) {
        self.context = context
        tick(now: .now)
        if machine.isRunning {
            scheduleTimerNotification()
        } else {
            cancelTimerNotification()
        }
        synchronizeLiveActivity()
    }

    func applicationDidBecomeActive() {
        tick()
        synchronizeLiveActivity(allowStart: true)
    }

    func setLiveActivityEnabled(_ enabled: Bool) {
        liveActivity.setEnabled(enabled)
        synchronizeLiveActivity(force: enabled)
    }

    func retryLiveActivity() { synchronizeLiveActivity(force: true) }

    func performActivityAction(timerID: String, phase: String, resume shouldResume: Bool) async throws {
        if context == nil {
            let container = try LifeOSModelContainer.make()
            activityContainer = container
            attach(context: container.mainContext)
        }
        // Catch up BEFORE validating the button. An expired focus must not be
        // paused at zero or let an old focus button pause the following break.
        tick()
        if PomodoroActivitySnapshot.acceptsAction(machine: machine, currentTimerID: currentActivityID,
                                                  requestedTimerID: timerID, phase: phase, resume: shouldResume) {
            if shouldResume { resume() } else { pause() }
        }
        synchronizeLiveActivity(allowStart: true)
        await liveActivity.waitForUpdates()
    }

    func tick(now: Date = .now) {
        remainingSeconds = machine.remainingSeconds(now: now)

        guard context != nil else { return }

        var handledEvent = false
        while let event = machine.tick(now: now) {
            handledEvent = true
            handle(event)
        }
        if handledEvent {
            persist()
        }
        remainingSeconds = machine.remainingSeconds(now: now)
    }

    // MARK: Actions

    func startFocus(task: StudyTask?) {
        guard machine.isIdle else { return }
        let configuration = preferences.configuration
        machine.startFocus(
            now: .now,
            taskTitle: task?.title,
            subject: task?.subject,
            configuration: configuration
        )
        defaults.set(machine.sessionID?.uuidString ?? UUID().uuidString, forKey: activityTimerKey)
        remainingSeconds = machine.phaseDurationSeconds
        persist()
        scheduleTimerNotification()
        Haptics.success()
    }

    func pause() {
        guard machine.isRunning else { return }
        machine.pause(now: .now)
        remainingSeconds = machine.remainingSeconds(now: .now)
        persist()
        cancelTimerNotification()
        Haptics.tap()
    }

    func resume() {
        guard machine.isPaused else { return }
        machine.resume(now: .now)
        remainingSeconds = machine.remainingSeconds(now: .now)
        persist()
        scheduleTimerNotification()
        Haptics.tap()
    }

    func end() {
        let event = machine.end(now: .now)
        if let event {
            handle(event)
        }
        persist()
        cancelTimerNotification()
        remainingSeconds = machine.remainingSeconds(now: .now)
        Haptics.tap()
    }

    func updatePreferences(_ newPreferences: StudyPreferences) {
        preferences = newPreferences
        savePreferences()
        if machine.isIdle {
            machine.updateConfiguration(newPreferences.configuration)
            remainingSeconds = machine.phaseDurationSeconds
            persist()
        }
    }

    // MARK: Events

    private func handle(_ event: PomodoroEvent) {
        switch event {
        case .focusCompleted(let completed):
            record(completed)
            setStatus("专注完成，开始休息")
            Haptics.success()
            scheduleTimerNotification()

        case .focusEndedEarly(let completed):
            record(completed)
            setStatus("已结束本轮专注")
            Haptics.success()
            cancelTimerNotification()

        case .breakCompleted(let wasLongBreak):
            setStatus(wasLongBreak ? "长休息结束，准备下一轮" : "休息结束，准备下一轮")
            Haptics.success()
            cancelTimerNotification()

        case .breakEnded:
            cancelTimerNotification()
        }
    }

    private func record(_ completed: CompletedFocus) {
        guard let context else { return }
        let existing = (try? context.fetch(FetchDescriptor<StudySession>()))?
            .contains { $0.id == completed.sessionID } ?? false
        guard !existing else { return }

        let session = StudySession(
            id: completed.sessionID,
            startedAt: completed.startedAt,
            endedAt: completed.endedAt,
            focusedSeconds: completed.focusedSeconds,
            kind: .focus,
            taskTitle: completed.taskTitle,
            subject: completed.subject
        )
        context.insert(session)
        try? context.save()
    }

    private func setStatus(_ message: String?) {
        statusMessage = message
        statusClearTask?.cancel()
        guard message != nil else { return }
        statusClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }

    // MARK: Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(machine) else { return }
        defaults.set(data, forKey: machineKey)
        NotificationCenter.default.post(name: .lifeOSWidgetTimerUpdated, object: nil)
        synchronizeLiveActivity()
    }

    private var currentActivityID: String {
        if let stored = defaults.string(forKey: activityTimerKey) { return stored }
        // Upgrade an already-running 0.10 timer without resetting its deadline.
        let identifier = machine.sessionID?.uuidString
            ?? "restored-\(machine.phaseStartedAt?.timeIntervalSince1970 ?? 0)"
        defaults.set(identifier, forKey: activityTimerKey)
        return identifier
    }

    private func synchronizeLiveActivity(allowStart: Bool? = nil, force: Bool = false) {
        let snapshot = PomodoroActivitySnapshot(machine: machine, timerID: currentActivityID)
        liveActivity.synchronize(snapshot,
                                 allowStart: allowStart ?? (UIApplication.shared.applicationState == .active),
                                 force: force)
    }

    private static func loadMachine(defaults: UserDefaults) -> PomodoroMachine? {
        guard let data = defaults.data(forKey: "lifeos.study.pomodoro.machine.v1") else { return nil }
        return try? JSONDecoder().decode(PomodoroMachine.self, from: data)
    }

    private func savePreferences() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: preferencesKey)
    }

    private static func loadPreferences(defaults: UserDefaults) -> StudyPreferences {
        guard let data = defaults.data(forKey: "lifeos.study.preferences.v1"),
              let prefs = try? JSONDecoder().decode(StudyPreferences.self, from: data) else {
            return StudyPreferences()
        }
        return prefs
    }

    // MARK: Notifications

    private func scheduleTimerNotification() {
        guard machine.isRunning else { return }

        let seconds = machine.remainingSeconds(now: .now)
        guard seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        switch machine.phase {
        case .focus:
            content.title = "专注完成"
            content.body = machine.taskTitle.map { "「\($0)」已专注 \(preferences.focusMinutes) 分钟" }
                ?? "本轮专注已完成，休息一下。"
        case .shortBreak:
            content.title = "休息结束"
            content.body = "准备好开始下一轮专注了吗？"
        case .longBreak:
            content.title = "长休息结束"
            content.body = "状态恢复，开始新的一轮吧。"
        }
        content.sound = .default

        let generation = UUID()
        notificationGeneration = generation
        let previous = notificationTask
        let expectedEndAt = machine.phaseEndAt
        notificationTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            guard notificationGeneration == generation else { return }
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationID])
            let granted = await self.ensureNotificationPermission()
            guard notificationGeneration == generation, machine.isRunning,
                  machine.phaseEndAt == expectedEndAt else { return }
            notificationDenied = !granted
            guard granted, let expectedEndAt else { return }
            let interval = expectedEndAt.timeIntervalSinceNow
            guard interval > 0 else { return }
            // Permission dialogs and queued mutations can take time. Preserve
            // the machine's deadline rather than starting a fresh old interval.
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
            let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
            try? await notificationCenter.add(request)
        }
    }

    private func cancelTimerNotification() {
        let generation = UUID()
        notificationGeneration = generation
        let previous = notificationTask
        notificationTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, notificationGeneration == generation else { return }
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationID])
            notificationCenter.removeDeliveredNotifications(withIdentifiers: [notificationID])
        }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationID])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [notificationID])
    }

    private func ensureNotificationPermission() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }
}
