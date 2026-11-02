import Foundation
import SwiftData

// Notification delivery is deliberately excluded from this in-memory data test.
@MainActor enum ScheduleNotificationManager { static func cancel(taskID: UUID) {} }

@main struct AIRecordDeletionQA {
    @MainActor static func main() throws {
        let schema = Schema([MoneyTransaction.self, StudyTask.self, StudySession.self, ScheduleTask.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let start = AIPlanProposal.localDate("2026-10-28", time: nil)!
        let next = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let middle = start.addingTimeInterval(3600)
        context.insert(MoneyTransaction(amountMinor: 100, occurredAt: start))
        context.insert(MoneyTransaction(amountMinor: 200, occurredAt: next))
        context.insert(StudyTask(title: "当天学习", plannedDate: middle))
        context.insert(StudyTask(title: "无日期", plannedDate: nil))
        context.insert(StudySession(startedAt: middle, endedAt: middle.addingTimeInterval(60), focusedSeconds: 60))
        context.insert(ScheduleTask(title: "当天日程", startAt: middle))
        context.insert(ScheduleTask(title: "次日日程", startAt: next))
        try context.save()
        let request = AIRecordDeletionRequest.parse(#"{"date":"2026-10-28","categories":["finance","study","schedule"]}"#)!
        for invalid in [#"{"date":"2026-02-30","categories":["finance"]}"#, #"{"date":"2026-10-28","categories":["settings"]}"#, #"{"date":"2026-10-28","categories":[]}"#] {
            precondition(AIRecordDeletionRequest.parse(invalid) == nil)
        }
        let preview = try AIRecordDeletion.preview(request, container: container)
        precondition(preview.rows.count == 4)
        // Preparing a preview must not mutate anything.
        let before = try ModelContext(container).fetchCount(FetchDescriptor<MoneyTransaction>())
        precondition(before == 2)
        // Records added after confirmation was prepared must survive.
        context.insert(MoneyTransaction(amountMinor: 300, occurredAt: middle))
        try context.save()
        let count = try AIRecordDeletion.delete(preview, container: container)
        precondition(count == 4)
        let fresh = ModelContext(container)
        let money = try fresh.fetch(FetchDescriptor<MoneyTransaction>())
        let study = try fresh.fetch(FetchDescriptor<StudyTask>())
        let sessions = try fresh.fetch(FetchDescriptor<StudySession>())
        let schedules = try fresh.fetch(FetchDescriptor<ScheduleTask>())
        precondition(money.count == 2 && Set(money.map(\.amountMinor)) == [200, 300])
        precondition(study.count == 1 && study[0].title == "无日期")
        precondition(sessions.isEmpty)
        precondition(schedules.count == 1 && schedules[0].title == "次日日程")
        let repeated = try AIRecordDeletion.delete(preview, container: container)
        precondition(repeated == 0)
        let finance = AIRecordDeletionRequest(date: "2026-10-28", categories: [.finance])
        let financePreview = try AIRecordDeletion.preview(finance, container: container)
        precondition(financePreview.rows.count == 1 && financePreview.rows[0].kind == "账目")
        print("Day deletion passed: preview read-only, exact-day bounds, category scope, undated preserved, later inserts preserved, repeat safe")
    }
}
