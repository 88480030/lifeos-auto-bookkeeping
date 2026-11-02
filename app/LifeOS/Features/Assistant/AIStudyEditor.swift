import Foundation
import SwiftData

@MainActor enum AIStudyEditor {
    /// Resolves the entire batch before changing anything. Date and exact old title
    /// identify one unfinished task; no deletes or financial edits. Dates and duration change only when explicitly supplied.
    static func apply(_ request: AIStudyEditRequest, container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var resolved: [(StudyTask, AIStudyEditRequest.Item)] = []
        var seen: Set<UUID> = []
        for item in request.items {
            if let time = item.time, !time.isEmpty {
                guard AIPlanProposal.localDate("2026-01-01", time: time) != nil,
                      !(item.newDate ?? item.date).isEmpty else { throw AIServiceError.invalidResponse }
            }
            guard item.newDate == nil || item.newDate!.isEmpty || AIPlanProposal.localDate(item.newDate!, time: nil) != nil,
                  item.minutes == nil || (1...1440).contains(item.minutes!) else { throw AIServiceError.invalidResponse }
            func records(on dateText: String) throws -> [StudyTask] {
                if dateText.isEmpty { return try context.fetch(FetchDescriptor<StudyTask>(predicate: #Predicate { $0.plannedDate == nil })) }
                guard let start = AIPlanProposal.localDate(dateText, time: nil),
                      let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { throw AIServiceError.invalidResponse }
                return try context.fetch(FetchDescriptor<StudyTask>(predicate: #Predicate { task in
                    if let date = task.plannedDate { return date >= start && date < end } else { return false }
                }))
            }
            let rows = try records(on: item.date)
            let old = rows.filter { $0.title == item.oldTitle && !$0.isCompleted }
            if old.isEmpty {
                let targets = try records(on: item.newDate ?? item.date)
                let already = targets.filter { $0.title == item.newTitle && (item.subject == nil || $0.subject == item.subject!) && (item.minutes == nil || $0.estimatedMinutes == item.minutes!) && (item.time == nil || $0.plannedStartMinute == startMinute(item.time!)) }
                if already.count == 1 { continue }
                throw AIStudyEditError.ambiguous
            }
            guard old.count == 1, seen.insert(old[0].id).inserted else { throw AIStudyEditError.ambiguous }
            resolved.append((old[0], item))
        }
        var changedCount = 0
        for (task, item) in resolved {
            let targetDate = item.newDate.map { $0.isEmpty ? nil : AIPlanProposal.localDate($0, time: nil) } ?? task.plannedDate
            let targetMinute = targetDate == nil ? nil : item.time.map { startMinute($0) } ?? task.plannedStartMinute
            guard task.title != item.newTitle || task.subject != (item.subject ?? task.subject)
                || task.plannedDate != targetDate || task.estimatedMinutes != (item.minutes ?? task.estimatedMinutes)
                || task.plannedStartMinute != targetMinute else { continue }
            task.title = item.newTitle
            if let subject = item.subject { task.subject = subject }
            if let newDate = item.newDate { task.plannedDate = newDate.isEmpty ? nil : AIPlanProposal.localDate(newDate, time: nil) }
            if let minutes = item.minutes { task.estimatedMinutes = minutes }
            if let time = item.time { task.plannedStartMinute = startMinute(time) }
            if task.plannedDate == nil { task.plannedStartMinute = nil }
            changedCount += 1
        }
        try context.save()
        return changedCount
    }
    private static func startMinute(_ time: String) -> Int? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : nil
    }
}
enum AIStudyEditError: LocalizedError {
    case ambiguous
    var errorDescription: String? { "未找到唯一匹配的未完成任务；本批未修改。请先读取对应日期的任务，使用原始标题重试。" }
}
