import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - File document

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupError.invalidData
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Summary

struct BackupImportSummary {
    var transactions = 0
    var budgets = 0
    var studyTasks = 0
    var studySessions = 0
    var scheduleTasks = 0
    var customCategories = 0
    var skipped = 0

    var text: String {
        """
        已导入：
        · 交易 \(transactions) 笔
        · 预算 \(budgets) 条
        · 学习任务 \(studyTasks) 个
        · 学习记录 \(studySessions) 条
        · 日程 \(scheduleTasks) 个
        · 自定义分类 \(customCategories) 个
        跳过重复记录：\(skipped) 条
        """
    }
}

// MARK: - Backup service

@MainActor
enum BackupService {
    static func makeArchive(context: ModelContext, categories: [CustomCategory]) throws -> BackupArchive {
        let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let studyTasks = try context.fetch(FetchDescriptor<StudyTask>())
        let studySessions = try context.fetch(FetchDescriptor<StudySession>())
        let scheduleTasks = try context.fetch(FetchDescriptor<ScheduleTask>())

        return BackupArchive(
            transactions: transactions.map(BackupTransaction.init),
            budgets: budgets.map(BackupBudget.init),
            studyTasks: studyTasks.map(BackupStudyTask.init),
            studySessions: studySessions.map(BackupStudySession.init),
            scheduleTasks: scheduleTasks.map(BackupScheduleTask.init),
            customCategories: categories.map {
                BackupCustomCategory(name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex)
            }
        )
    }

    static func importArchive(
        _ archive: BackupArchive,
        context: ModelContext,
        categoryStore: CustomCategoryStore
    ) throws -> BackupImportSummary {
        var summary = BackupImportSummary()

        let existingTransactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        var transactionIDs = Set(existingTransactions.map(\.id))
        var externalIDs = Set(existingTransactions.compactMap { $0.externalID }.filter { !$0.isEmpty })

        for dto in archive.transactions {
            if transactionIDs.contains(dto.id) {
                summary.skipped += 1
                continue
            }
            if let externalID = dto.externalID, !externalID.isEmpty, externalIDs.contains(externalID) {
                summary.skipped += 1
                continue
            }
            context.insert(dto.makeModel())
            transactionIDs.insert(dto.id)
            if let externalID = dto.externalID, !externalID.isEmpty {
                externalIDs.insert(externalID)
            }
            summary.transactions += 1
        }

        let existingBudgets = try context.fetch(FetchDescriptor<Budget>())
        var budgetKeys = Set(existingBudgets.map { budgetKey(monthKey: $0.monthKey, currencyCode: $0.currencyCode) })
        for dto in archive.budgets {
            let key = budgetKey(monthKey: dto.monthKey, currencyCode: dto.currencyCode)
            if budgetKeys.contains(key) {
                summary.skipped += 1
                continue
            }
            context.insert(dto.makeModel())
            budgetKeys.insert(key)
            summary.budgets += 1
        }

        let existingStudyTasks = try context.fetch(FetchDescriptor<StudyTask>())
        var studyTaskIDs = Set(existingStudyTasks.map(\.id))
        for dto in archive.studyTasks {
            if studyTaskIDs.contains(dto.id) {
                summary.skipped += 1
                continue
            }
            context.insert(dto.makeModel())
            studyTaskIDs.insert(dto.id)
            summary.studyTasks += 1
        }

        let existingSessions = try context.fetch(FetchDescriptor<StudySession>())
        var sessionIDs = Set(existingSessions.map(\.id))
        for dto in archive.studySessions {
            if sessionIDs.contains(dto.id) {
                summary.skipped += 1
                continue
            }
            context.insert(dto.makeModel())
            sessionIDs.insert(dto.id)
            summary.studySessions += 1
        }

        let existingSchedule = try context.fetch(FetchDescriptor<ScheduleTask>())
        var scheduleIDs = Set(existingSchedule.map(\.id))
        for dto in archive.scheduleTasks {
            if scheduleIDs.contains(dto.id) {
                summary.skipped += 1
                continue
            }
            context.insert(dto.makeModel())
            scheduleIDs.insert(dto.id)
            summary.scheduleTasks += 1
        }

        for category in archive.customCategories {
            if categoryStore.add(name: category.name, symbol: category.symbol, colorHex: category.colorHex) {
                summary.customCategories += 1
            } else {
                summary.skipped += 1
            }
        }

        try context.save()
        return summary
    }

    private static func budgetKey(monthKey: String, currencyCode: String) -> String {
        "\(monthKey)|\(currencyCode.uppercased())"
    }
}
