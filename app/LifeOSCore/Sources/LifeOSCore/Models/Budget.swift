import Foundation
import SwiftData

/// 月度预算。每个「月份 + 币种」逻辑上应只有一条，由业务层保证唯一性。
@Model
public final class Budget {
    @Attribute(.unique) public var id: UUID
    /// 形如 "2026-10"。
    public var monthKey: String
    public var amountMinor: Int
    public var currencyCode: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        monthKey: String,
        amountMinor: Int,
        currencyCode: String = "CNY",
        createdAt: Date = .now
    ) {
        self.id = id
        self.monthKey = monthKey
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode.uppercased()
        self.createdAt = createdAt
    }

    public var money: MoneyAmount {
        MoneyAmount(minorUnits: amountMinor, currencyCode: currencyCode)
    }
}
