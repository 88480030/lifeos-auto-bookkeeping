import Combine
import Foundation
import SwiftData
import UserNotifications
import UIKit

@MainActor
enum ScheduleNotificationManager {
    static let identifierPrefix = "lifeos.schedule."
    private static let notificationCenter = UNUserNotificationCenter.current()

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationCenter.notificationSettings().authorizationStatus
    }

    static func requestPermissionIfNeeded() async -> Bool {
        let status = await notificationCenter.notificationSettings().authorizationStatus
        switch status {
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

    private static var isRefreshing = false
    private static var refreshAgain = false

    static func rescheduleAll(context: ModelContext, limit: Int = 60) async {
        if isRefreshing { refreshAgain = true; return }
        isRefreshing = true
        let backgroundLease = PlanReminderBackgroundLease()
        backgroundLease.start()
        defer { isRefreshing = false; backgroundLease.end() }
        repeat {
            refreshAgain = false
            let settings = await notificationCenter.notificationSettings()
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
            let reader = ModelContext(context.container)
            reader.autosaveEnabled = false
            guard let life = try? reader.fetch(FetchDescriptor<ScheduleTask>()),
                  let study = try? reader.fetch(FetchDescriptor<StudyTask>()) else {
                PlanReminderStatus.shared.errorMessage = "读取计划失败，提醒暂未更新，请重新打开应用。"
                return
            }
            let plans = PlanReminder.upcoming(scheduleTasks: life, studyTasks: study, limit: min(60, limit))
            let pending = await notificationCenter.pendingNotificationRequests()
            let owned = pending.filter { isPlanIdentifier($0.identifier) }
            let desiredIDs = Set(plans.map(\.id))
            // Remove only deleted/completed/evicted entries. Unchanged reminders
            // stay armed, including while a different request is being updated.
            notificationCenter.removePendingNotificationRequests(withIdentifiers:
                owned.map(\.identifier).filter { !desiredIDs.contains($0) })
            let existing = Dictionary(uniqueKeysWithValues: owned.map { ($0.identifier, $0) })
            var failures = 0
            for plan in plans {
                let content = UNMutableNotificationContent()
                content.title = plan.isStudy ? "15 分钟后开始学习" : "15 分钟后的生活日程"
                content.body = "\(AppFormatters.time(plan.startAt)) · \(plan.title)"
                content.sound = .default
                if let old = existing[plan.id], old.content.title == content.title,
                   old.content.body == content.body,
                   let oldDate = (old.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(),
                   abs(oldDate.timeIntervalSince(plan.fireAt)) < 1 { continue }
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.fireAt)
                let request = UNNotificationRequest(identifier: plan.id, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                do { try await notificationCenter.add(request) }
                catch { failures += 1 }
            }
            let confirmed = await notificationCenter.pendingNotificationRequests().filter { isPlanIdentifier($0.identifier) }
            PlanReminderStatus.shared.scheduledCount = confirmed.count
            PlanReminderStatus.shared.nextFireAt = confirmed.compactMap {
                ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            }.min()
            failures = max(failures, desiredIDs.subtracting(Set(confirmed.map(\.identifier))).count)
            PlanReminderStatus.shared.errorMessage = failures == 0 ? nil : "有 \(failures) 条提醒未能排入，请重新打开应用重试。"
            #if DEBUG
            print("[PlanReminders] queued=\(confirmed.count) failures=\(failures) leadMinutes=15")
            #endif

        } while refreshAgain
    }

    static func cancel(taskID: UUID) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier(for: taskID)])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier(for: taskID)])
    }

    static func cancel(tasks: [ScheduleTask]) {
        let identifiers = tasks.map { identifier(for: $0.id) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private static func isPlanIdentifier(_ id: String) -> Bool {
        id.hasPrefix(identifierPrefix) || id.hasPrefix("lifeos.study.")
    }

    private static func identifier(for id: UUID) -> String {
        identifierPrefix + id.uuidString
    }
}


@MainActor
final class PlanReminderStatus: ObservableObject {
    static let shared = PlanReminderStatus()
    @Published var scheduledCount = 0
    @Published var nextFireAt: Date?
    @Published var errorMessage: String?
}


/// Finish saved-plan notification updates when the user immediately locks the phone.
@MainActor
private final class PlanReminderBackgroundLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    func start() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Update plan reminders") { [weak self] in
            Task { @MainActor in self?.end() }
        }
    }
    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
