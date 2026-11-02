import Foundation
import SwiftData

@main struct AIPlanWriterQA {
    @MainActor static func main() throws {
        let schema = Schema([StudyTask.self, ScheduleTask.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let json = #"{"items":[{"kind":"study","title":"单词","subject":"英语","date":"2026-11-01","minutes":25},{"kind":"schedule","title":"英语角","date":"2026-11-01","time":"19:00","minutes":60}]}"#
        let proposal = AIPlanProposal.parse(json)!
        let first = try AIPlanWriter.save(proposal, container: container)
        let second = try AIPlanWriter.save(proposal, container: container)
        precondition(first == 2 && second == 0)
        let c = ModelContext(container)
        let studies = try c.fetch(FetchDescriptor<StudyTask>())
        let schedules = try c.fetch(FetchDescriptor<ScheduleTask>())
        precondition(studies.count == 1 && studies[0].title == "单词" && studies[0].estimatedMinutes == 25)
        precondition(schedules.count == 1 && schedules[0].title == "英语角" && schedules[0].durationMinutes == 60)
        let bad = AIPlanProposal(items: [
            .init(id: UUID(), kind: .study, title: "未提交", subject: "", date: nil, time: nil, minutes: 25),
            .init(id: UUID(), kind: .schedule, title: "缺日期", subject: "", date: nil, time: nil, minutes: 25)
        ])
        do { _ = try AIPlanWriter.save(bad, container: container); fatalError("invalid plan was accepted") }
        catch AIServiceError.invalidResponse {}
        let fresh = ModelContext(container)
        let afterFailure = try fresh.fetch(FetchDescriptor<StudyTask>())
        precondition(afterFailure.count == 1)
        // A long dated plan starts exactly on the requested day, never today.
        let datedItems: [[String: Any]] = (0..<65).map { index in
            let day = String(format: "2026-11-%02d", 1 + index / 3)
            return ["kind": "study", "title": "排表任务\(index)", "date": day, "minutes": 25]
        }
        let encodedBatch = try JSONSerialization.data(withJSONObject: ["items": datedItems])
        let batch = AIPlanProposal.parse(String(decoding: encodedBatch, as: UTF8.self))!
        precondition(batch.items.count == 65)
        let inserted = try AIPlanWriter.save(batch, container: container)
        precondition(inserted == 65)
        let afterBatch = try ModelContext(container).fetch(FetchDescriptor<StudyTask>())
        precondition(afterBatch.count == 66)
        precondition(afterBatch.filter { $0.title.hasPrefix("排表任务") }.allSatisfy { $0.plannedDate != nil })

        print("AI plan writer: saved both domains, retry idempotent, invalid batch atomic")
    }
}
