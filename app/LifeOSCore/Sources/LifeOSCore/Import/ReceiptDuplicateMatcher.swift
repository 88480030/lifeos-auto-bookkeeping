import Foundation
import SwiftData

public struct ReceiptDuplicateCheck: Equatable, Sendable {
    public let exactIDs: [UUID]
    public let possibleIDs: [UUID]

    public var hasExactMatch: Bool { !exactIDs.isEmpty }
    public var hasPossibleMatch: Bool { !possibleIDs.isEmpty }
}

/// Exact source identifiers block re-import; amount/date/merchant similarities are warnings only.
public enum ReceiptDuplicateMatcher {
    /// CSV 导入也检查已保存的截图来源，防止导入顺序不同导致同笔交易重复。
    /// 相同交易号但不同金额、币种或收支方向仍交由用户复核，不静默丢弃退款。
    public static func isExactImportDuplicate(_ item: ImportedTransaction, existing: [MoneyTransaction]) -> Bool {
        check(
            amountMinor: item.amountMinor,
            currencyCode: item.currencyCode,
            kind: item.kind,
            occurredAt: item.occurredAt,
            merchant: item.merchant,
            externalID: item.externalID,
            existing: existing
        ).hasExactMatch
    }

    public static func check(
        amountMinor: Int,
        currencyCode: String,
        kind: TransactionKind,
        occurredAt: Date?,
        merchant: String,
        externalID: String?,
        existing: [MoneyTransaction],
        hasExplicitTime: Bool = true,
        calendar: Calendar = .current
    ) -> ReceiptDuplicateCheck {
        let canonical = canonicalExternalID(externalID)
        let normalizedMerchant = normalizeMerchant(merchant)
        var exact: [UUID] = [], possible: [UUID] = []
        for transaction in existing {
            if let canonical, canonical == canonicalExternalID(transaction.externalID) {
                // A refund can refer to the original purchase's transaction number.
                // The identical OCR fingerprint remains exact, while reused official
                // IDs with a different direction or amount need human review.
                if canonical.hasPrefix("receipt:sha256:")
                    || (transaction.kind == kind && transaction.amountMinor == amountMinor
                        && transaction.currencyCode.uppercased() == currencyCode.uppercased()) {
                    exact.append(transaction.id)
                } else {
                    possible.append(transaction.id)
                }
                continue
            }
            guard amountMinor > 0, transaction.amountMinor == amountMinor,
                  transaction.currencyCode.uppercased() == currencyCode.uppercased(), transaction.kind == kind,
                  let occurredAt, !normalizedMerchant.isEmpty,
                  normalizeMerchant(transaction.merchant) == normalizedMerchant,
                  calendar.isDate(transaction.occurredAt, inSameDayAs: occurredAt) else { continue }
            if !hasExplicitTime || abs(transaction.occurredAt.timeIntervalSince(occurredAt)) <= 120 {
                possible.append(transaction.id)
            }
        }
        return ReceiptDuplicateCheck(exactIDs: exact.sorted { $0.uuidString < $1.uuidString },
                                     possibleIDs: possible.sorted { $0.uuidString < $1.uuidString })
    }

    private static func canonicalExternalID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        for provider in ["wechat", "alipay"] {
            let receiptPrefix = "receipt:\(provider):tx:"
            if trimmed.hasPrefix(receiptPrefix) { return "\(provider):" + trimmed.dropFirst(receiptPrefix.count) }
        }
        return trimmed
    }

    private static func normalizeMerchant(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }
}


public enum ReceiptAutomaticRecordOutcome: Equatable {
    case saved(UUID)
    case duplicate(UUID)
    case needsReview(String)
}

/// Automatic recording skips exact duplicates; similar amounts do not require confirmation.
@MainActor
public enum ReceiptAutomaticRecorder {
    public static func record(
        _ receipt: ReceiptParseResult,
        in context: ModelContext,
        capturedAt: Date = .now
    ) throws -> ReceiptAutomaticRecordOutcome {
        guard receipt.permitsAutomaticRecording,
              let amount = receipt.suggestedAmount else {
            return .needsReview("未能确定已完成交易的实际金额，请核对截图后保存。")
        }
        let channel = receipt.channel ?? .other
        let date = receipt.occurredAt ?? capturedAt
        let merchant = receipt.merchant ?? ""
        let existing = try context.fetch(FetchDescriptor<MoneyTransaction>())
        let duplicate = ReceiptDuplicateMatcher.check(
            amountMinor: amount.amountMinor, currencyCode: amount.currencyCode, kind: receipt.kind,
            occurredAt: date, merchant: merchant, externalID: receipt.externalID,
            existing: existing, hasExplicitTime: receipt.hasExplicitTime
        )
        if let id = duplicate.exactIDs.first { return .duplicate(id) }
        var note = "快捷指令自动记账"
        if receipt.recipientConfirmationPending { note += "；收款方待确认" }
        if receipt.occurredAt == nil { note += "；未识别日期，按截图时刻记录" }
        if receipt.merchant == nil { note += "；商家未识别" }
        if receipt.channel == nil { note += "；支付渠道未识别" }
        let transaction = MoneyTransaction(
            amountMinor: amount.amountMinor, currencyCode: amount.currencyCode, kind: receipt.kind,
            categoryRaw: receipt.kind == .income ? "其他收入" : receipt.categoryRaw,
            channel: channel, occurredAt: date, note: note, merchant: merchant,
            externalID: receipt.externalID
        )
        context.insert(transaction)
        do {
            try context.save()
            return .saved(transaction.id)
        } catch {
            context.delete(transaction)
            throw error
        }
    }
}
