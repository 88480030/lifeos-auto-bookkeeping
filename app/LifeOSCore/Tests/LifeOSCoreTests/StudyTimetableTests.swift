import Foundation
import Testing
@testable import LifeOSCore

@Test func studyTimetableSurvivesBackupAndOrdersByStart() throws {
    let day = Date.now
    let late = StudyTask(title: "晚", estimatedMinutes: 45, plannedDate: day, plannedStartMinute: 23 * 60 + 30)
    let early = StudyTask(title: "早", estimatedMinutes: 60, plannedDate: day, plannedStartMinute: 8 * 60)
    let untimed = StudyTask(title: "待安排", plannedDate: day)
    #expect(late.plannedTimeRange == "23:30–次日 00:15")
    #expect(early.plannedTimeRange == "08:00–09:00")
    #expect(untimed.plannedTimeRange == nil)
    #expect(StudyPlanning.tasks([late, untimed, early], on: day).map(\.title) == ["早", "晚", "待安排"])
    let encoded = try JSONEncoder().encode(BackupStudyTask(early))
    let restored = try JSONDecoder().decode(BackupStudyTask.self, from: encoded).makeModel()
    #expect(restored.plannedStartMinute == 480)
    #expect(restored.plannedTimeRange == "08:00–09:00")
    var old = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    old.removeValue(forKey: "plannedStartMinute")
    let oldData = try JSONSerialization.data(withJSONObject: old)
    #expect(try JSONDecoder().decode(BackupStudyTask.self, from: oldData).plannedStartMinute == nil)
}
