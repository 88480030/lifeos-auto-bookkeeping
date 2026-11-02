import Foundation
import SwiftData

@MainActor enum AIStudyTopicReplacement {
    struct Snapshot: Codable, Equatable {
        let id: UUID
        let title: String
        let subject: String
        let estimatedMinutes: Int
        let plannedDate: Date?
        let plannedStartMinute: Int?
        let isCompleted: Bool
        let completedAt: Date?
        let createdAt: Date

        init(_ task: StudyTask) {
            id = task.id; title = task.title; subject = task.subject
            estimatedMinutes = task.estimatedMinutes; plannedDate = task.plannedDate
            plannedStartMinute = task.plannedStartMinute; isCompleted = task.isCompleted
            completedAt = task.completedAt; createdAt = task.createdAt
        }
        func makeTask() -> StudyTask {
            StudyTask(id: id, title: title, subject: subject, estimatedMinutes: estimatedMinutes,
                      plannedDate: plannedDate, plannedStartMinute: plannedStartMinute,
                      isCompleted: isCompleted, completedAt: completedAt, createdAt: createdAt)
        }
    }
    private struct Journal: Codable {
        let old: [Snapshot]
        let inserted: [Snapshot]
    }
    struct Result {
        let deletedCount: Int
        let insertedCount: Int
        let untimedCount: Int
        let undoID: UUID?
    }
    enum Error: LocalizedError {
        case invalid, noMatches, tooMany, changed
        var errorDescription: String? {
            switch self {
            case .invalid: "日期或计划格式不正确，本次没有修改。"
            case .noMatches: "没有找到该日期范围内符合主题的未完成学习任务，本次没有修改。"
            case .tooMany: "匹配任务超过 200 项，请缩小日期范围；本次没有修改。"
            case .changed: "任务已发生变化或已撤销，无法安全撤销；现有记录没有改动。"
            }
        }
    }
    private static func journalURL(_ id: UUID, directory: URL?) throws -> URL {
        let base = try directory ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent("study-topic-undo", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(id.uuidString + ".json")
    }
    static func apply(_ request: AIStudyTopicReplacementRequest, container: ModelContainer,
                      directory: URL? = nil) throws -> Result {
        guard let from = AIPlanProposal.localDate(request.startDate, time: nil),
              let to = AIPlanProposal.localDate(request.endDate, time: nil), from < to else { throw Error.invalid }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let rows = try context.fetch(FetchDescriptor<StudyTask>())
        let matches = rows.filter { task in
            guard !task.isCompleted, let date = task.plannedDate else { return false }
            return date >= from && date < to && task.title.contains(request.titleContains)
        }
        guard !matches.isEmpty else { throw Error.noMatches }
        guard matches.count <= 200 else { throw Error.tooMany }
        let replacements: [StudyTask] = try request.items.map { item in
            guard let date = AIPlanProposal.localDate(item.date, time: nil), date >= from, date < to else { throw Error.invalid }
            let components = item.time?.split(separator: ":").compactMap { Int($0) }
            let givenMinute = components.flatMap { $0.count == 2 ? $0[0] * 60 + $0[1] : nil }
            let preservedMinute = matches.filter { $0.plannedDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }
                .compactMap(\.plannedStartMinute).filter { (0..<1440).contains($0) }.min()
            return StudyTask(title: item.title, subject: item.subject, estimatedMinutes: item.minutes,
                             plannedDate: date, plannedStartMinute: givenMinute ?? preservedMinute)
        }
        // Repeating the same request must not replace identical tasks again.
        var unmatched = matches
        for replacement in replacements {
            if let index = unmatched.firstIndex(where: { existing in
                existing.title == replacement.title && existing.subject == replacement.subject &&
                existing.estimatedMinutes == replacement.estimatedMinutes &&
                existing.plannedStartMinute == replacement.plannedStartMinute &&
                existing.plannedDate == replacement.plannedDate
            }) { unmatched.remove(at: index) }
        }
        if unmatched.isEmpty && matches.count == replacements.count {
            return Result(deletedCount: 0, insertedCount: 0,
                          untimedCount: replacements.filter { $0.plannedStartMinute == nil }.count, undoID: nil)
        }
        let id = UUID()
        let journal = Journal(old: matches.map(Snapshot.init), inserted: replacements.map(Snapshot.init))
        let file = try journalURL(id, directory: directory)
        try JSONEncoder().encode(journal).write(to: file, options: [.atomic, .completeFileProtection])
        for task in matches { context.delete(task) }
        for task in replacements { context.insert(task) }
        do { try context.save() }
        catch { try? FileManager.default.removeItem(at: file); throw error }
        return Result(deletedCount: matches.count, insertedCount: replacements.count,
                      untimedCount: replacements.filter { $0.plannedStartMinute == nil }.count, undoID: id)
    }
    static func undo(_ id: UUID, container: ModelContainer, directory: URL? = nil) throws {
        let file = try journalURL(id, directory: directory)
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: file))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let all = try context.fetch(FetchDescriptor<StudyTask>())
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        guard journal.old.allSatisfy({ byID[$0.id] == nil }),
              journal.inserted.allSatisfy({ snapshot in byID[snapshot.id].map { Snapshot($0) == snapshot } ?? false }) else {
            throw Error.changed
        }
        for snapshot in journal.inserted { context.delete(byID[snapshot.id]!) }
        for snapshot in journal.old { context.insert(snapshot.makeTask()) }
        try context.save()
        try? FileManager.default.removeItem(at: file)
    }

    /// Recovery remains available even if the app closed before saving the chat reply.
    static func latestUndoID(container: ModelContainer, directory: URL? = nil) throws -> UUID? {
        let folder = try journalURL(UUID(), directory: directory).deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let all = try context.fetch(FetchDescriptor<StudyTask>())
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        for file in files.prefix(100) {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: file),
                  let journal = try? JSONDecoder().decode(Journal.self, from: data) else { continue }
            if journal.old.allSatisfy({ byID[$0.id] == nil }) &&
               journal.inserted.allSatisfy({ snapshot in byID[snapshot.id].map { Snapshot($0) == snapshot } ?? false }) {
                return id
            }
            // An unfinished pre-commit journal can be skipped. A committed
            // replacement that was later edited must block undoing older work.
            if journal.old.allSatisfy({ byID[$0.id] != nil }) &&
               journal.inserted.allSatisfy({ byID[$0.id] == nil }) { continue }
            return nil
        }
        return nil
    }
}
