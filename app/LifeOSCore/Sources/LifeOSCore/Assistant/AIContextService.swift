import Foundation
import SwiftData

/// User-selected groups of local data. No group is implicitly enabled.
public enum AIDataDomain: String, Codable, CaseIterable, Hashable, Sendable {
    case finance, study, schedule
}

/// A bounded page for one type of record. An empty successful page is distinct from failure.
public struct AIContextSection: Codable, Sendable {
    public let status: String
    public let dateField: String
    public let offset: Int
    public let limit: Int
    public let hasMore: Bool
    public let records: [[String: String]]
    public let error: String?
}

public struct AIContextSnapshot: Codable, Sendable {
    public let generatedAt: String
    public let startInclusive: String?
    public let endExclusive: String?
    public let sections: [String: AIContextSection]
    public let currentFocus: [String: String]?
    public let note: String

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

/// Read-only, bounded projections. It has no networking and never reads credentials.
/// Date filters apply to transaction time, session start, schedule start, and planned date for study tasks, and creation time
/// for budgets. `offset` is applied separately to each selected record type.
@MainActor public enum AIContextService {
    public static func capture(context: ModelContext, domains: Set<AIDataDomain>,
                               start: Date? = nil, end: Date? = nil, limit: Int = 40,
                               offset: Int = 0, studyTitleContains: String? = nil, machine: PomodoroMachine? = nil,
                               now: Date = .now) -> AIContextSnapshot {
        let safeLimit = min(max(limit, 1), 100)
        let safeOffset = max(offset, 0)
        var sections: [String: AIContextSection] = [:]
        let invalid = start != nil && end != nil && start! >= end!
        if domains.contains(.finance) {
            sections["transactions"] = read(context, descriptor: transactionDescriptor(start, end), dateField: "occurredAt", limit: safeLimit, offset: safeOffset, invalid: invalid) { t in
                ["amountMinor": String(t.amountMinor), "currency": t.currencyCode,
                 "direction": t.kindRaw, "category": bounded(t.categoryDisplayName),
                 "channel": t.channelRaw, "occurredAt": date(t.occurredAt),
                 "merchant": bounded(t.merchant), "note": bounded(t.note)]
            }
            sections["budgets"] = read(context, descriptor: budgetDescriptor(start, end), dateField: "createdAt", limit: safeLimit, offset: safeOffset, invalid: invalid) { b in
                ["month": b.monthKey, "amountMinor": String(b.amountMinor),
                 "currency": b.currencyCode, "createdAt": date(b.createdAt)]
            }
        }
        if domains.contains(.study) {
            if studyTitleContains == nil {
            sections["studySessions"] = read(context, descriptor: sessionDescriptor(start, end), dateField: "startedAt", limit: safeLimit, offset: safeOffset, invalid: invalid) { s in
                ["startedAt": date(s.startedAt), "endedAt": date(s.endedAt),
                 "focusedSeconds": String(s.focusedSeconds), "kind": s.kindRaw,
                 "taskTitle": bounded(s.taskTitle ?? ""), "subject": bounded(s.subject ?? "")]
            }
            }
            sections["studyTasks"] = read(context, descriptor: studyTaskDescriptor(start, end, topic: studyTitleContains), dateField: "plannedDate", limit: safeLimit, offset: safeOffset, invalid: invalid) { t in
                ["title": bounded(t.title), "subject": bounded(t.subject), "estimatedMinutes": String(t.estimatedMinutes),
                 "plannedDate": t.plannedDate.map(localDay) ?? "",
                 "time": t.plannedStartMinute.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) } ?? "",
                 "timeRange": t.plannedTimeRange ?? "", "isCompleted": String(t.isCompleted),
                 "completedAt": t.completedAt.map(date) ?? "", "createdAt": date(t.createdAt)]
            }
        }
        if domains.contains(.schedule) {
            sections["schedule"] = read(context, descriptor: scheduleDescriptor(start, end), dateField: "startAt", limit: safeLimit, offset: safeOffset, invalid: invalid) { t in
                ["title": bounded(t.title), "startAt": date(t.startAt), "durationMinutes": String(t.durationMinutes),
                 "priority": t.priority.displayName, "isCompleted": String(t.isCompleted), "notes": bounded(t.notes),
                 "reminderMinutesBefore": t.reminderMinutesBefore.map(String.init) ?? "",
                 "repeatRule": bounded(t.repeatRuleRaw ?? "")]
            }
        }
        var focus: [String: String]? = nil
        if domains.contains(.study), let machine {
            focus = ["phase": machine.phase.rawValue, "state": machine.state.rawValue,
                     "remainingSeconds": String(machine.remainingSeconds(now: now)),
                     "taskTitle": bounded(machine.taskTitle ?? ""), "subject": bounded(machine.subject ?? ""),
                     "endAt": machine.phaseEndAt.map(date) ?? ""]
        }
        return AIContextSnapshot(generatedAt: date(now), startInclusive: start.map(date), endExclusive: end.map(date),
                                 sections: sections, currentFocus: focus,
                                 note: "仅包含用户允许的类别；每类分页且可能截断，不能把缺失记录当作零。本机时区为 \(TimeZone.current.identifier)。学习任务的plannedDate是本地日历日期YYYY-MM-DD，不要转换成前一天；其余时间戳带本地偏移。学习任务按计划日期筛选，无计划日期的任务不属于任何一天；预算按创建时间筛选。查询完整排表需要同时查询学习和日程类别。金额为对应币种的最小单位，不做汇率换算。")
    }

    private static func read<T: PersistentModel>(_ context: ModelContext, descriptor: FetchDescriptor<T>,
                                                  dateField: String, limit: Int, offset: Int, invalid: Bool,
                                                  map: (T) -> [String: String]) -> AIContextSection {
        guard !invalid else {
            return AIContextSection(status: "error", dateField: dateField, offset: offset, limit: limit,
                                    hasMore: false, records: [], error: "日期范围无效")
        }
        var descriptor = descriptor
        descriptor.fetchLimit = limit + 1
        descriptor.fetchOffset = offset
        do {
            let values = try context.fetch(descriptor)
            return AIContextSection(status: "ok", dateField: dateField, offset: offset, limit: limit,
                                    hasMore: values.count > limit, records: values.prefix(limit).map(map), error: nil)
        } catch {
            return AIContextSection(status: "error", dateField: dateField, offset: offset, limit: limit,
                                    hasMore: false, records: [], error: "本地数据读取失败")
        }
    }

    private static func bounded(_ value: String) -> String {
        value.count > 1000 ? String(value.prefix(1000)) + "…[内容截断]" : value
    }
    private static func date(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: value)
    }
    private static func localDay(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }

    private static func transactionDescriptor(_ start: Date?, _ end: Date?) -> FetchDescriptor<MoneyTransaction> {
        var d = FetchDescriptor<MoneyTransaction>(sortBy: [SortDescriptor(\MoneyTransaction.occurredAt, order: .reverse)])
        if let start, let end { d.predicate = #Predicate { $0.occurredAt >= start && $0.occurredAt < end } }
        else if let start { d.predicate = #Predicate { $0.occurredAt >= start } }
        else if let end { d.predicate = #Predicate { $0.occurredAt < end } }
        return d
    }
    private static func budgetDescriptor(_ start: Date?, _ end: Date?) -> FetchDescriptor<Budget> {
        var d = FetchDescriptor<Budget>(sortBy: [SortDescriptor(\Budget.createdAt, order: .reverse)])
        if let start, let end { d.predicate = #Predicate { $0.createdAt >= start && $0.createdAt < end } }
        else if let start { d.predicate = #Predicate { $0.createdAt >= start } }
        else if let end { d.predicate = #Predicate { $0.createdAt < end } }
        return d
    }
    private static func sessionDescriptor(_ start: Date?, _ end: Date?) -> FetchDescriptor<StudySession> {
        var d = FetchDescriptor<StudySession>(sortBy: [SortDescriptor(\StudySession.startedAt, order: .reverse)])
        if let start, let end { d.predicate = #Predicate { $0.startedAt >= start && $0.startedAt < end } }
        else if let start { d.predicate = #Predicate { $0.startedAt >= start } }
        else if let end { d.predicate = #Predicate { $0.startedAt < end } }
        return d
    }
    private static func studyTaskDescriptor(_ start: Date?, _ end: Date?, topic: String?) -> FetchDescriptor<StudyTask> {
        var d = FetchDescriptor<StudyTask>(sortBy: [SortDescriptor(\StudyTask.plannedDate), SortDescriptor(\StudyTask.createdAt)])
        if let topic {
            if let start, let end {
                d.predicate = #Predicate { task in
                    if let date = task.plannedDate { return date >= start && date < end && task.title.contains(topic) } else { return false }
                }
            } else if let start {
                d.predicate = #Predicate { task in
                    if let date = task.plannedDate { return date >= start && task.title.contains(topic) } else { return false }
                }
            } else if let end {
                d.predicate = #Predicate { task in
                    if let date = task.plannedDate { return date < end && task.title.contains(topic) } else { return false }
                }
            } else {
                d.predicate = #Predicate { task in task.title.contains(topic) }
            }
            return d
        }
        if let start, let end { d.predicate = #Predicate { task in
            if let date = task.plannedDate { return date >= start && date < end } else { return false }
        } }
        else if let start { d.predicate = #Predicate { task in
            if let date = task.plannedDate { return date >= start } else { return false }
        } }
        else if let end { d.predicate = #Predicate { task in
            if let date = task.plannedDate { return date < end } else { return false }
        } }
        return d
    }
    private static func scheduleDescriptor(_ start: Date?, _ end: Date?) -> FetchDescriptor<ScheduleTask> {
        var d = FetchDescriptor<ScheduleTask>(sortBy: [SortDescriptor(\ScheduleTask.startAt, order: .reverse)])
        if let start, let end { d.predicate = #Predicate { $0.startAt >= start && $0.startAt < end } }
        else if let start { d.predicate = #Predicate { $0.startAt >= start } }
        else if let end { d.predicate = #Predicate { $0.startAt < end } }
        return d
    }
}
