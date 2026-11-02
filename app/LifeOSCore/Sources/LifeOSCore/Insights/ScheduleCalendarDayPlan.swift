import Foundation

/// Calendar markers keep non-study events distinct from planned learning work.
public struct ScheduleCalendarDayPlan: Equatable, Sendable {
    public let lifeCount: Int
    public let studyCount: Int
    public var hasLifeEvents: Bool { lifeCount > 0 }

    public init(lifeCount: Int = 0, studyCount: Int = 0) {
        self.lifeCount = max(0, lifeCount)
        self.studyCount = max(0, studyCount)
    }

    /// Life markers describe saved events, including completed events. Search
    /// filters may narrow study counts but must not erase a day's event marker.
    public static func grouped(scheduleTasks: [ScheduleTask], studyCounts: [Date: Int],
                               calendar: Calendar = .current) -> [Date: Self] {
        var life: [Date: Int] = [:]
        var study: [Date: Int] = [:]
        for task in scheduleTasks { life[calendar.startOfDay(for: task.startAt), default: 0] += 1 }
        for (date, count) in studyCounts {
            study[calendar.startOfDay(for: date), default: 0] += max(0, count)
        }
        return Dictionary(uniqueKeysWithValues: Set(life.keys).union(study.keys).map { date in
            (date, Self(lifeCount: life[date] ?? 0, studyCount: study[date] ?? 0))
        })
    }
}
