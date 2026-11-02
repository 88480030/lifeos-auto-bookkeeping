import Foundation
import SwiftData

/// 一次番茄钟或休息的真实记录。计时以时间戳为准，focusedSeconds 为最终有效时长。
@Model
public final class StudySession {
    @Attribute(.unique) public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var focusedSeconds: Int
    /// StudySessionKind 的原始值。
    public var kindRaw: String
    public var taskTitle: String?
    public var subject: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        focusedSeconds: Int,
        kind: StudySessionKind = .focus,
        taskTitle: String? = nil,
        subject: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.focusedSeconds = max(0, focusedSeconds)
        self.kindRaw = kind.rawValue
        self.taskTitle = taskTitle
        self.subject = subject
        self.createdAt = createdAt
    }

    public var kind: StudySessionKind {
        get { StudySessionKind(rawValue: kindRaw) ?? .focus }
        set { kindRaw = newValue.rawValue }
    }

    public var durationMinutes: Int {
        focusedSeconds / 60
    }
}
