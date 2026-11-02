import Foundation

// MARK: - Backup archive

public struct BackupArchive: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var exportedAt: Date
    public var transactions: [BackupTransaction]
    public var budgets: [BackupBudget]
    public var studyTasks: [BackupStudyTask]
    public var studySessions: [BackupStudySession]
    public var scheduleTasks: [BackupScheduleTask]
    public var customCategories: [BackupCustomCategory]

    public init(
        schemaVersion: Int = BackupArchive.currentSchemaVersion,
        exportedAt: Date = .now,
        transactions: [BackupTransaction] = [],
        budgets: [BackupBudget] = [],
        studyTasks: [BackupStudyTask] = [],
        studySessions: [BackupStudySession] = [],
        scheduleTasks: [BackupScheduleTask] = [],
        customCategories: [BackupCustomCategory] = []
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.transactions = transactions
        self.budgets = budgets
        self.studyTasks = studyTasks
        self.studySessions = studySessions
        self.scheduleTasks = scheduleTasks
        self.customCategories = customCategories
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> BackupArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(BackupArchive.self, from: data)
        guard archive.schemaVersion == currentSchemaVersion else {
            throw BackupError.unsupportedVersion(archive.schemaVersion)
        }
        return archive
    }
}

public enum BackupError: Error, LocalizedError {
    case unsupportedVersion(Int)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "备份文件版本 \(version) 不受支持，请使用较新版本的 LifeOS 打开。"
        case .invalidData:
            "备份文件内容无法读取，可能已损坏。"
        }
    }
}

// MARK: - DTOs

public struct BackupTransaction: Codable, Sendable, Hashable {
    public var id: UUID
    public var amountMinor: Int
    public var currencyCode: String
    public var kindRaw: String
    public var categoryRaw: String
    public var channelRaw: String
    public var occurredAt: Date
    public var note: String
    public var merchant: String
    public var externalID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(_ model: MoneyTransaction) {
        id = model.id
        amountMinor = model.amountMinor
        currencyCode = model.currencyCode
        kindRaw = model.kindRaw
        categoryRaw = model.categoryRaw
        channelRaw = model.channelRaw
        occurredAt = model.occurredAt
        note = model.note
        merchant = model.merchant
        externalID = model.externalID
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    public func makeModel() -> MoneyTransaction {
        MoneyTransaction(
            id: id,
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            kind: TransactionKind(rawValue: kindRaw) ?? .expense,
            categoryRaw: categoryRaw,
            channel: PaymentChannel(rawValue: channelRaw) ?? .other,
            occurredAt: occurredAt,
            note: note,
            merchant: merchant,
            externalID: externalID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public struct BackupBudget: Codable, Sendable, Hashable {
    public var id: UUID
    public var monthKey: String
    public var amountMinor: Int
    public var currencyCode: String
    public var createdAt: Date

    public init(_ model: Budget) {
        id = model.id
        monthKey = model.monthKey
        amountMinor = model.amountMinor
        currencyCode = model.currencyCode
        createdAt = model.createdAt
    }

    public func makeModel() -> Budget {
        Budget(
            id: id,
            monthKey: monthKey,
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            createdAt: createdAt
        )
    }
}

public struct BackupStudyTask: Codable, Sendable, Hashable {
    public var id: UUID
    public var title: String
    public var subject: String
    public var estimatedMinutes: Int
    public var plannedDate: Date?
    public var plannedStartMinute: Int? = nil
    public var isCompleted: Bool
    public var completedAt: Date?
    public var createdAt: Date

    public init(_ model: StudyTask) {
        id = model.id
        title = model.title
        subject = model.subject
        estimatedMinutes = model.estimatedMinutes
        plannedDate = model.plannedDate
        plannedStartMinute = model.plannedStartMinute
        isCompleted = model.isCompleted
        completedAt = model.completedAt
        createdAt = model.createdAt
    }

    public func makeModel() -> StudyTask {
        StudyTask(
            id: id,
            title: title,
            subject: subject,
            estimatedMinutes: estimatedMinutes,
            plannedDate: plannedDate,
            plannedStartMinute: plannedStartMinute,
            isCompleted: isCompleted,
            completedAt: completedAt,
            createdAt: createdAt
        )
    }
}

public struct BackupStudySession: Codable, Sendable, Hashable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var focusedSeconds: Int
    public var kindRaw: String
    public var taskTitle: String?
    public var subject: String?
    public var createdAt: Date

    public init(_ model: StudySession) {
        id = model.id
        startedAt = model.startedAt
        endedAt = model.endedAt
        focusedSeconds = model.focusedSeconds
        kindRaw = model.kindRaw
        taskTitle = model.taskTitle
        subject = model.subject
        createdAt = model.createdAt
    }

    public func makeModel() -> StudySession {
        StudySession(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            focusedSeconds: focusedSeconds,
            kind: StudySessionKind(rawValue: kindRaw) ?? .focus,
            taskTitle: taskTitle,
            subject: subject,
            createdAt: createdAt
        )
    }
}

public struct BackupScheduleTask: Codable, Sendable, Hashable {
    public var id: UUID
    public var title: String
    public var startAt: Date
    public var durationMinutes: Int
    public var priorityRaw: Int
    public var isCompleted: Bool
    public var notes: String
    public var reminderMinutesBefore: Int?
    public var repeatRuleRaw: String?
    public var seriesID: String?
    public var createdAt: Date

    public init(_ model: ScheduleTask) {
        id = model.id
        title = model.title
        startAt = model.startAt
        durationMinutes = model.durationMinutes
        priorityRaw = model.priorityRaw
        isCompleted = model.isCompleted
        notes = model.notes
        reminderMinutesBefore = model.reminderMinutesBefore
        repeatRuleRaw = model.repeatRuleRaw
        seriesID = model.seriesID
        createdAt = model.createdAt
    }

    public func makeModel() -> ScheduleTask {
        ScheduleTask(
            id: id,
            title: title,
            startAt: startAt,
            durationMinutes: durationMinutes,
            priority: TaskPriority(rawValue: priorityRaw) ?? .normal,
            isCompleted: isCompleted,
            notes: notes,
            reminderMinutesBefore: reminderMinutesBefore,
            repeatRuleRaw: repeatRuleRaw,
            seriesID: seriesID,
            createdAt: createdAt
        )
    }
}

public struct BackupCustomCategory: Codable, Sendable, Hashable {
    public var name: String
    public var symbol: String
    public var colorHex: UInt32

    public init(name: String, symbol: String, colorHex: UInt32) {
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
    }
}
