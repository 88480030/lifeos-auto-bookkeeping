import Foundation
import SwiftData

/// 日程 / 待办任务。
@Model
public final class ScheduleTask {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var startAt: Date
    public var durationMinutes: Int
    /// TaskPriority 的 rawValue。
    public var priorityRaw: Int
    public var isCompleted: Bool
    public var notes: String
    /// 提前多少分钟提醒；nil 表示不提醒。
    public var reminderMinutesBefore: Int?
    /// 重复规则原始值，第四阶段实现。
    public var repeatRuleRaw: String?
    /// 重复任务系列标识；单次任务为 nil。
    public var seriesID: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        startAt: Date,
        durationMinutes: Int = 30,
        priority: TaskPriority = .normal,
        isCompleted: Bool = false,
        notes: String = "",
        reminderMinutesBefore: Int? = nil,
        repeatRuleRaw: String? = nil,
        seriesID: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.durationMinutes = max(0, durationMinutes)
        self.priorityRaw = priority.rawValue
        self.isCompleted = isCompleted
        self.notes = notes
        self.reminderMinutesBefore = reminderMinutesBefore
        self.repeatRuleRaw = repeatRuleRaw
        self.seriesID = seriesID
        self.createdAt = createdAt
    }

    public var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    public var endAt: Date {
        startAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}
