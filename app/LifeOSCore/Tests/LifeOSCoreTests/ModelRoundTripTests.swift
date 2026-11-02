import Foundation
import SwiftData
import Testing
@testable import LifeOSCore

@Test func inMemoryContainerSupportsAllCoreModels() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = ModelContext(container)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    let transaction = MoneyTransaction(
        amountMinor: 12345,
        currencyCode: "CNY",
        kind: .expense,
        categoryRaw: BuiltInCategory.dining.rawValue,
        channel: .wechat,
        occurredAt: now,
        note: "午餐"
    )
    let budget = Budget(monthKey: "2026-10", amountMinor: 300_000, currencyCode: "CNY")
    let studyTask = StudyTask(title: "背单词", subject: "英语", estimatedMinutes: 25, plannedDate: now)
    let session = StudySession(
        startedAt: now,
        endedAt: now.addingTimeInterval(1500),
        focusedSeconds: 1500,
        kind: .focus,
        taskTitle: "背单词",
        subject: "英语"
    )
    let schedule = ScheduleTask(
        title: "整理房间",
        startAt: now.addingTimeInterval(3600),
        durationMinutes: 30,
        priority: .high,
        reminderMinutesBefore: 10
    )

    context.insert(transaction)
    context.insert(budget)
    context.insert(studyTask)
    context.insert(session)
    context.insert(schedule)
    try context.save()

    let transactions = try context.fetchCount(FetchDescriptor<MoneyTransaction>())
    let budgets = try context.fetchCount(FetchDescriptor<Budget>())
    let studyTasks = try context.fetchCount(FetchDescriptor<StudyTask>())
    let sessions = try context.fetchCount(FetchDescriptor<StudySession>())
    let scheduleTasks = try context.fetchCount(FetchDescriptor<ScheduleTask>())

    #expect(transactions == 1)
    #expect(budgets == 1)
    #expect(studyTasks == 1)
    #expect(sessions == 1)
    #expect(scheduleTasks == 1)

    #expect(transaction.kind == .expense)
    #expect(transaction.categoryDisplayName == "餐饮")
    #expect(transaction.money.minorUnits == 12345)
    #expect(session.durationMinutes == 25)
    #expect(schedule.endAt.timeIntervalSince(schedule.startAt) == 1800)
    #expect(budget.money.currencyCode == "CNY")
}

@Test func storedRecordsCanBeEditedAndDeleted() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = ModelContext(container)

    let transaction = MoneyTransaction(amountMinor: 500, currencyCode: "CNY", note: "原备注")
    context.insert(transaction)
    try context.save()

    transaction.amountMinor = 800
    transaction.note = "修改后的备注"
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<MoneyTransaction>())
    #expect(fetched.count == 1)
    #expect(fetched[0].amountMinor == 800)
    #expect(fetched[0].note == "修改后的备注")

    context.delete(transaction)
    try context.save()

    let remaining = try context.fetchCount(FetchDescriptor<MoneyTransaction>())
    #expect(remaining == 0)
}
