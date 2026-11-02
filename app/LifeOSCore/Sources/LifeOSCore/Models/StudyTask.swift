import Foundation
import SwiftData

/// 学习任务 / 学习计划。
@Model
public final class StudyTask {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var subject: String
    public var estimatedMinutes: Int
    /// 计划学习的日期（只使用其中的年月日）。
    public var plannedDate: Date?
    /// Local wall-clock minute from midnight; nil means not timed.
    public var plannedStartMinute: Int? = nil
    public var isCompleted: Bool
    public var completedAt: Date?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        subject: String = "",
        estimatedMinutes: Int = 25,
        plannedDate: Date? = nil,
        plannedStartMinute: Int? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.subject = subject
        self.estimatedMinutes = estimatedMinutes
        self.plannedDate = plannedDate
        self.plannedStartMinute = plannedStartMinute
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
    }
    public var plannedTimeRange: String? {
        guard plannedDate != nil, let minute = plannedStartMinute, (0..<1440).contains(minute) else { return nil }
        func clock(_ value: Int) -> String { String(format: "%02d:%02d", (value % 1440) / 60, value % 60) }
        let end = minute + estimatedMinutes
        return clock(minute) + "–" + (end >= 1440 ? "次日 " : "") + clock(end)
    }
}
