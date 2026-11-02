import Foundation
import SwiftData
import Testing
@testable import LifeOSCore

@Test @MainActor func aiContextRespectsDomainConsentAndNeverExportsTransactionIDs() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = container.mainContext
    context.insert(MoneyTransaction(amountMinor: 1234, currencyCode: "CNY", merchant: "咖啡店", externalID: "secret-external-id"))
    context.insert(ScheduleTask(title: "私人会议", startAt: .now))
    try context.save()
    let finance = AIContextService.capture(context: context, domains: [.finance])
    let text = try finance.jsonString()
    #expect(finance.sections["transactions"]?.records.first?["amountMinor"] == "1234")
    #expect(finance.sections["schedule"] == nil)
    #expect(!text.contains("私人会议"))
    #expect(!text.contains("secret-external-id"))
    let disabled = AIContextService.capture(context: context, domains: [])
    #expect(disabled.sections.isEmpty)
    #expect(disabled.currentFocus == nil)
}

@Test @MainActor func aiContextReportsPaginationAndAppliesExplicitDateRange() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = container.mainContext
    let base = Date(timeIntervalSince1970: 1_000_000)
    for n in 0..<5 {
        context.insert(MoneyTransaction(amountMinor: n + 1, occurredAt: base.addingTimeInterval(Double(n) * 60)))
    }
    try context.save()
    let page = AIContextService.capture(context: context, domains: [.finance], start: base.addingTimeInterval(60), end: base.addingTimeInterval(240), limit: 2)
    #expect(page.sections["transactions"]?.records.map { $0["amountMinor"] ?? "" } == ["4", "3"])
    #expect(page.sections["transactions"]?.hasMore == true)
    let next = AIContextService.capture(context: context, domains: [.finance], start: base.addingTimeInterval(60), end: base.addingTimeInterval(240), limit: 2, offset: 2)
    #expect(next.sections["transactions"]?.records.map { $0["amountMinor"] ?? "" } == ["2"])
    #expect(next.sections["transactions"]?.hasMore == false)
}

@Test @MainActor func aiContextDistinguishesInvalidRangeFromEmptyAndLimitsRequestSize() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = container.mainContext
    let now = Date()
    let invalid = AIContextService.capture(context: context, domains: [.schedule], start: now, end: now, limit: 1_000_000, offset: -1)
    #expect(invalid.sections["schedule"]?.status == "error")
    #expect(invalid.sections["schedule"]?.error == "日期范围无效")
    #expect(invalid.sections["schedule"]?.limit == 100)
    #expect(invalid.sections["schedule"]?.offset == 0)
    let empty = AIContextService.capture(context: context, domains: [.schedule])
    #expect(empty.sections["schedule"]?.status == "ok")
    #expect(empty.sections["schedule"]?.records.isEmpty == true)
    #expect(empty.sections["schedule"]?.error == nil)
}

@Test @MainActor func aiContextIncludesFocusOnlyWhenStudyAllowed() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let now = Date(timeIntervalSince1970: 1_000_000)
    var machine = PomodoroMachine()
    machine.startFocus(now: now, taskTitle: "背单词", subject: "英语")
    let result = AIContextService.capture(context: container.mainContext, domains: [.study], machine: machine, now: now.addingTimeInterval(60))
    #expect(result.currentFocus?["taskTitle"] == "背单词")
    #expect(result.currentFocus?["remainingSeconds"] == "1440")
    let withheld = AIContextService.capture(context: container.mainContext, domains: [.finance], machine: machine)
    #expect(withheld.currentFocus == nil)
}

@Test @MainActor func aiContextCoversAllFiveModelsAndFlagsLongFieldTruncation() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = container.mainContext
    let now = Date()
    context.insert(MoneyTransaction(amountMinor: 100, note: String(repeating: "字", count: 1200)))
    context.insert(Budget(monthKey: "2026-10", amountMinor: 30000))
    context.insert(StudySession(startedAt: now, endedAt: now, focusedSeconds: 900, subject: "英语"))
    context.insert(StudyTask(title: "复习"))
    context.insert(ScheduleTask(title: "上课", startAt: now))
    try context.save()
    let snapshot = AIContextService.capture(context: context, domains: [.finance, .study, .schedule])
    #expect(snapshot.sections.count == 5)
    for key in ["transactions", "budgets", "studySessions", "studyTasks", "schedule"] {
        #expect(snapshot.sections[key]?.status == "ok")
        #expect(snapshot.sections[key]?.records.count == 1)
    }
    #expect(snapshot.sections["transactions"]?.records.first?["note"]?.hasSuffix("[内容截断]") == true)
}

@Test @MainActor func aiStudyDateQueryUsesPlannedDateRatherThanCreationDate() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = container.mainContext
    let calendar = Calendar(identifier: .gregorian)
    let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30))!
    let end = calendar.date(byAdding: .day, value: 1, to: start)!
    context.insert(StudyTask(title: "30号英语", plannedDate: start, createdAt: start.addingTimeInterval(-86400)))
    context.insert(StudyTask(title: "未排期", plannedDate: nil, createdAt: start))
    context.insert(StudyTask(title: "31号任务", plannedDate: end, createdAt: start))
    try context.save()
    let snapshot = AIContextService.capture(context: context, domains: [.study], start: start, end: end)
    #expect(snapshot.sections["studyTasks"]?.records.map { $0["title"] ?? "" } == ["30号英语"])
    #expect(snapshot.sections["studyTasks"]?.dateField == "plannedDate")
    #expect(snapshot.sections["studyTasks"]?.records.first?["plannedDate"] == "2026-10-30")
}

@Test @MainActor func topicFilterRunsBeforePaginationAndExcludesOtherSubjects() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = container.mainContext
    let day = Date(timeIntervalSince1970: 1_793_289_600)
    for n in 0..<160 {
        context.insert(StudyTask(title: "英语 \(n)", subject: "英语", plannedDate: day, createdAt: day.addingTimeInterval(Double(n))))
    }
    for n in 0..<69 {
        context.insert(StudyTask(title: "写作练习 景点 \(n)", subject: "写作练习", plannedDate: day, createdAt: day.addingTimeInterval(Double(200 + n))))
    }
    try context.save()
    let page = AIContextService.capture(context: context, domains: [.study], limit: 100, studyTitleContains: "写作练习")
    #expect(page.sections["studyTasks"]?.status == "ok")
    #expect(page.sections["studyTasks"]?.records.count == 69)
    #expect(page.sections["studyTasks"]?.hasMore == false)
    #expect(page.sections["studyTasks"]?.records.allSatisfy { $0["title"]?.contains("写作练习") == true } == true)
    #expect(page.sections["studySessions"] == nil)
    let later = AIContextService.capture(context: context, domains: [.study], limit: 30, offset: 30, studyTitleContains: "写作练习")
    #expect(later.sections["studyTasks"]?.records.count == 30)
    #expect(later.sections["studyTasks"]?.hasMore == true)
}
