import Foundation
import SwiftData

@main struct AIStudyEditorQA {
    @MainActor static func main() throws {
        let schema = Schema([StudyTask.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let c = ModelContext(container)
        let day = AIPlanProposal.localDate("2026-11-21", time: nil)!
        let task = StudyTask(title: "错误第18章", subject: "旧科目", estimatedMinutes: 60, plannedDate: day)
        c.insert(task)
        c.insert(StudyTask(title: "其他任务", plannedDate: day))
        try c.save()
        let valid = AIStudyEditRequest.parse(#"{"items":[{"date":"2026-11-21","old_title":"错误第18章","new_title":"第2—12章复盘","subject":"正确科目"}]}"#)!
        let invalidBatch = AIStudyEditRequest(items: valid.items + [.init(date: "2026-11-21", oldTitle: "不存在", newTitle: "不要创建", subject: nil)])
        do { _ = try AIStudyEditor.apply(invalidBatch, container: container); fatalError("unresolved batch applied") }
        catch AIStudyEditError.ambiguous {}
        let untouched = try ModelContext(container).fetch(FetchDescriptor<StudyTask>())
        precondition(untouched.contains { $0.title == "错误第18章" })
        let first = try AIStudyEditor.apply(valid, container: container)
        let repeatCount = try AIStudyEditor.apply(valid, container: container)
        precondition(first == 1 && repeatCount == 0)
        let fresh = try ModelContext(container).fetch(FetchDescriptor<StudyTask>())
        let edited = fresh.first { $0.id == task.id }!
        precondition(fresh.count == 2 && edited.title == "第2—12章复盘" && edited.subject == "正确科目")
        precondition(edited.plannedDate == day && edited.estimatedMinutes == 60 && !edited.isCompleted)
        precondition(AIStudyEditRequest.parse(#"{"items":[{"date":"2026-11-21","old_title":"x","new_title":""}]}"#) == nil)
        let moved = AIStudyEditRequest.parse(#"{"items":[{"date":"2026-11-21","old_title":"第2—12章复盘","new_title":"调整后的任务","new_date":"2026-11-20","minutes":45}]}"#)!
        let movedCount = try AIStudyEditor.apply(moved, container: container)
        let movedRetry = try AIStudyEditor.apply(moved, container: container)
        precondition(movedCount == 1 && movedRetry == 0)
        let movedRows = try ModelContext(container).fetch(FetchDescriptor<StudyTask>())
        let changed = movedRows.first { $0.id == task.id }!
        precondition(changed.plannedDate == AIPlanProposal.localDate("2026-11-20", time: nil) && changed.estimatedMinutes == 45)

        let timed = AIStudyEditRequest.parse(#"{"items":[{"date":"2026-11-20","old_title":"调整后的任务","new_title":"调整后的任务","time":"08:30"}]}"#)!
        let timedCount = try AIStudyEditor.apply(timed, container: container)
        let repeatedTimeCount = try AIStudyEditor.apply(timed, container: container)
        precondition(timedCount == 1 && repeatedTimeCount == 0)
        let timedTask = try ModelContext(container).fetch(FetchDescriptor<StudyTask>()).first { $0.id == task.id }!
        precondition(timedTask.plannedStartMinute == 510 && timedTask.plannedTimeRange == "08:30–09:15")
        precondition(AIStudyEditRequest.parse(#"{"items":[{"date":"2026-11-20","old_title":"x","new_title":"x","time":"25:30"}]}"#) == nil)
        let clear = AIStudyEditRequest.parse(#"{"items":[{"date":"2026-11-20","old_title":"调整后的任务","new_title":"调整后的任务","time":""}]}"#)!
        let clearedCount = try AIStudyEditor.apply(clear, container: container)
        let repeatedClearCount = try AIStudyEditor.apply(clear, container: container)
        precondition(clearedCount == 1 && repeatedClearCount == 0)
        let clearedRows = try ModelContext(container).fetch(FetchDescriptor<StudyTask>())
        precondition(clearedRows.first { $0.id == task.id }!.plannedStartMinute == nil)
        let undate = AIStudyEditRequest.parse(#"{"items":[{"date":"2026-11-20","old_title":"调整后的任务","new_title":"调整后的任务","new_date":""}]}"#)!
        let undatedCount = try AIStudyEditor.apply(undate, container: container)
        precondition(undatedCount == 1)
        let undatedRows = try ModelContext(container).fetch(FetchDescriptor<StudyTask>())
        precondition(undatedRows.first { $0.id == task.id }!.plannedDate == nil)
        print("Study edits passed: exact date/title, atomic resolution, idempotence, other tasks and duration preserved")
    }
}
