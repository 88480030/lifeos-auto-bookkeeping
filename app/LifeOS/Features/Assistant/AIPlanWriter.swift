import Foundation
import SwiftData

@MainActor
enum AIPlanWriter {
    /// Uses stable item IDs and a separate context so retries are idempotent and
    /// failures never roll back edits elsewhere in the application.
    static func save(_ proposal: AIPlanProposal, container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var inserted = 0
        for item in proposal.items {
            let id = item.id
            if item.kind == .study {
                var query = FetchDescriptor<StudyTask>(predicate: #Predicate { $0.id == id })
                query.fetchLimit = 1
                if try !context.fetch(query).isEmpty { continue }
                let date = item.date.flatMap { AIPlanProposal.localDate($0, time: nil) }
                context.insert(StudyTask(id: id, title: item.title, subject: item.subject,
                                         estimatedMinutes: item.minutes, plannedDate: date,
                                         plannedStartMinute: item.time.flatMap { value in
                                             let parts = value.split(separator: ":").compactMap { Int($0) }
                                             return parts.count == 2 ? parts[0] * 60 + parts[1] : nil
                                         }))
            } else {
                var query = FetchDescriptor<ScheduleTask>(predicate: #Predicate { $0.id == id })
                query.fetchLimit = 1
                if try !context.fetch(query).isEmpty { continue }
                guard let date = item.date, let time = item.time,
                      let start = AIPlanProposal.localDate(date, time: time) else { throw AIServiceError.invalidResponse }
                context.insert(ScheduleTask(id: id, title: item.title, startAt: start, durationMinutes: item.minutes))
            }
            inserted += 1
        }
        try context.save()
        return inserted
    }
}
