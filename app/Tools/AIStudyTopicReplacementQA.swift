import Foundation
import SwiftData

@main struct AIStudyTopicReplacementQA {
    @MainActor static func main() throws {
        let schema = Schema([StudyTask.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ctx = ModelContext(container)
        let first = AIPlanProposal.localDate("2031-04-01", time: nil)!
        let formatter = DateFormatter(); formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
        var items: [[String: Any]] = []
        for offset in 0..<23 {
            let day = Calendar.current.date(byAdding: .day, value: offset, to: first)!
            for segment in 1...3 {
                ctx.insert(StudyTask(title: "写作练习：景点\(offset) 第\(segment)段", subject: "写作练习", estimatedMinutes: 30, plannedDate: day, plannedStartMinute: 1260))
            }
            ctx.insert(StudyTask(title: "英语：第\(offset)页", subject: "英语", plannedDate: day, plannedStartMinute: 435))
            items.append(["title":"写作练习：景点\(offset) 整篇", "subject":"写作练习", "date":formatter.string(from: day), "minutes":30])
        }
        ctx.insert(StudyTask(title: "写作练习：已完成", subject: "写作练习", plannedDate: first, isCompleted: true))
        try ctx.save()
        let payload: [String: Any] = ["start_date":"2031-04-01", "end_date":"2031-04-24", "title_contains":"写作练习", "daily_count":1, "items":items]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        guard let request = AIStudyTopicReplacementRequest.parse(text) else { fatalError("valid request rejected") }
        var incomplete = payload; incomplete["items"] = Array(items.dropLast())
        let incompleteText = String(decoding: try JSONSerialization.data(withJSONObject: incomplete), as: UTF8.self)
        precondition(AIStudyTopicReplacementRequest.parse(incompleteText) == nil, "missing day must reject")
        let result = try AIStudyTopicReplacement.apply(request, container: container, directory: dir)
        precondition(result.deletedCount == 69 && result.insertedCount == 23 && result.untimedCount == 0)
        let available = try AIStudyTopicReplacement.latestUndoID(container: container, directory: dir)
        precondition(available == result.undoID)
        let after = try ModelContext(container).fetch(FetchDescriptor<StudyTask>())
        precondition(after.filter { $0.subject == "英语" }.count == 23)
        precondition(after.filter { $0.title.contains("整篇") }.count == 23)
        precondition(after.filter { $0.title.contains("整篇") }.allSatisfy { $0.plannedStartMinute == 1260 })
        precondition(after.contains { $0.title == "写作练习：已完成" && $0.isCompleted })
        let repeatResult = try AIStudyTopicReplacement.apply(request, container: container, directory: dir)
        precondition(repeatResult.deletedCount == 0 && repeatResult.undoID == nil, "repeated request must be idempotent")
        let editContext = ModelContext(container)
        let changed = try editContext.fetch(FetchDescriptor<StudyTask>()).first { $0.title.contains("整篇") }!
        let name = changed.title; changed.title = "用户后来修改"; try editContext.save()
        let blocked = try AIStudyTopicReplacement.latestUndoID(container: container, directory: dir)
        precondition(blocked == nil)
        do { try AIStudyTopicReplacement.undo(result.undoID!, container: container, directory: dir); fatalError("must reject edited replacements") }
        catch AIStudyTopicReplacement.Error.changed {}
        let repair = ModelContext(container)
        let task = try repair.fetch(FetchDescriptor<StudyTask>()).first { $0.id == changed.id }!
        task.title = name; try repair.save()
        let repaired = try AIStudyTopicReplacement.latestUndoID(container: container, directory: dir)
        precondition(repaired == result.undoID)
        try AIStudyTopicReplacement.undo(result.undoID!, container: container, directory: dir)
        let afterUndo = try AIStudyTopicReplacement.latestUndoID(container: container, directory: dir)
        precondition(afterUndo == nil)
        let restored = try ModelContext(container).fetch(FetchDescriptor<StudyTask>())
        precondition(restored.count == 93 && restored.filter { $0.title.contains("整篇") }.isEmpty)
        precondition(restored.filter { $0.subject == "英语" }.count == 23)
        print("Topic replacement QA passed: 23 days, 69 targeted tasks, unrelated and completed preserved, idempotence, conflict-safe undo")
    }
}
