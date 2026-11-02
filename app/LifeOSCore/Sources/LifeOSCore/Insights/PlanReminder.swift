import Foundation

public struct PlanReminder: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let startAt: Date
    public let fireAt: Date
    public let isStudy: Bool

    public static func upcoming(scheduleTasks: [ScheduleTask], studyTasks: [StudyTask],
                                now: Date = .now, calendar: Calendar = .current, limit: Int = 60) -> [Self] {
        func reminder(id: String, title: String, start: Date, study: Bool) -> Self? {
            let fire = start.addingTimeInterval(-15 * 60)
            guard fire > now else { return nil }
            return Self(id: id, title: title, startAt: start, fireAt: fire, isStudy: study)
        }
        let life = scheduleTasks.filter { !$0.isCompleted }.compactMap {
            reminder(id: "lifeos.schedule.\($0.id)", title: $0.title, start: $0.startAt, study: false)
        }
        let learning = studyTasks.filter { !$0.isCompleted }.compactMap { task -> Self? in
            guard let date = task.plannedDate, let minute = task.plannedStartMinute,
                  (0..<1440).contains(minute),
                  let start = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date) else { return nil }
            return reminder(id: "lifeos.study.\(task.id)", title: task.title, start: start, study: true)
        }
        return Array((life + learning).sorted {
            $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt
        }.prefix(max(0, limit)))
    }
}
