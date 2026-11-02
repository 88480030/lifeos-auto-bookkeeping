import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

extension Notification.Name {
    static let lifeOSWidgetTimerUpdated = Notification.Name("lifeos.widget.timer.updated")
}

/// Observes committed local changes without moving or sharing the SwiftData store.
struct WidgetSnapshotSyncView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task { synchronize() }
            .onChange(of: scenePhase) { _, _ in synchronize() }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { _ in synchronize() }
            .onReceive(NotificationCenter.default.publisher(for: .lifeOSWidgetTimerUpdated).receive(on: RunLoop.main)) { _ in synchronize() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in synchronize() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification).receive(on: RunLoop.main)) { _ in synchronize() }
    }

    @MainActor private func synchronize() {
        let now = Date()
        let interval = Calendar.current.dateInterval(of: .day, for: now)
            ?? DateInterval(start: Calendar.current.startOfDay(for: now), duration: 86_400)
        let start = interval.start
        let end = interval.end
        do {
            let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>(
                predicate: #Predicate { $0.occurredAt >= start && $0.occurredAt < end }
            ))
            let tasks = try context.fetch(FetchDescriptor<ScheduleTask>(
                predicate: #Predicate { $0.startAt >= start && $0.startAt < end }
            ))
            let snapshot = LifeOSWidgetSnapshotBuilder.make(
                transactions: transactions, scheduleTasks: tasks,
                machine: StudyTimerEngine.shared.machine, now: now
            )
            if LifeOSWidgetStore.writeIfChanged(snapshot) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            // Do not replace a valid snapshot with fabricated empty data after a fetch failure.
        }
    }
}
