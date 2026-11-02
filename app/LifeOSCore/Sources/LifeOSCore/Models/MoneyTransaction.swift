import Foundation
import SwiftData

/// 一笔真实的收入或支出记录。
@Model
public final class MoneyTransaction {
    @Attribute(.unique) public var id: UUID
    /// 最小货币单位金额，例如 ¥12.34 保存为 1234。
    public var amountMinor: Int
    /// ISO 4217 币种代码，例如 CNY、JPY。
    public var currencyCode: String
    /// TransactionKind 的原始值。
    public var kindRaw: String
    /// 内置分类原始值，或用户自定义分类名称。
    public var categoryRaw: String
    /// PaymentChannel 的原始值。
    public var channelRaw: String
    public var occurredAt: Date
    public var note: String
    public var merchant: String
    /// 导入账单时的外部交易标识，用于去重。手动记账为 nil。
    public var externalID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        amountMinor: Int,
        currencyCode: String = "CNY",
        kind: TransactionKind = .expense,
        categoryRaw: String = BuiltInCategory.other.rawValue,
        channel: PaymentChannel = .other,
        occurredAt: Date = .now,
        note: String = "",
        merchant: String = "",
        externalID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode.uppercased()
        self.kindRaw = kind.rawValue
        self.categoryRaw = categoryRaw
        self.channelRaw = channel.rawValue
        self.occurredAt = occurredAt
        self.note = note
        self.merchant = merchant
        self.externalID = externalID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    public var channel: PaymentChannel {
        get { PaymentChannel(rawValue: channelRaw) ?? .other }
        set { channelRaw = newValue.rawValue }
    }

    public var money: MoneyAmount {
        MoneyAmount(minorUnits: amountMinor, currencyCode: currencyCode)
    }

    public var categoryDisplayName: String {
        BuiltInCategory(rawValue: categoryRaw)?.displayName ?? categoryRaw
    }
}
