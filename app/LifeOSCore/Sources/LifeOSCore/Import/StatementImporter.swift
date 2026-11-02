import Foundation
import CoreFoundation
import CryptoKit

// MARK: - CSV

public enum CSV {
    /// 解析 CSV 文本，支持引号、引号内逗号/换行、转义引号与 CRLF。
    public static func rows(from text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                    } else {
                        inQuotes = false
                        index += 1
                    }
                } else {
                    field.append(character)
                    index += 1
                }
                continue
            }

            switch character {
            case "\"":
                inQuotes = true
                index += 1
            case ",":
                row.append(field)
                field = ""
                index += 1
            case "\r":
                if index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                index += 1
            case "\n":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                index += 1
            default:
                field.append(character)
                index += 1
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

// MARK: - Model

public enum StatementSource: String, Codable, Sendable {
    case wechat
    case alipay

    public var displayName: String {
        switch self {
        case .wechat: "微信支付"
        case .alipay: "支付宝"
        }
    }
}

public struct ImportedTransaction: Identifiable, Hashable, Sendable {
    public let id: String
    public var source: StatementSource
    public var occurredAt: Date
    public var kind: TransactionKind
    public var amountMinor: Int
    public var currencyCode: String
    public var categoryRaw: String
    public var channel: PaymentChannel
    public var merchant: String
    public var note: String
    public var externalID: String
    public var isRefund: Bool
    public var isTransfer: Bool

    public init(
        id: String,
        source: StatementSource,
        occurredAt: Date,
        kind: TransactionKind,
        amountMinor: Int,
        currencyCode: String = "CNY",
        categoryRaw: String,
        channel: PaymentChannel,
        merchant: String,
        note: String,
        externalID: String,
        isRefund: Bool,
        isTransfer: Bool
    ) {
        self.id = id
        self.source = source
        self.occurredAt = occurredAt
        self.kind = kind
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.categoryRaw = categoryRaw
        self.channel = channel
        self.merchant = merchant
        self.note = note
        self.externalID = externalID
        self.isRefund = isRefund
        self.isTransfer = isTransfer
    }
}

public struct StatementParseResult: Sendable, Identifiable {
    public let id = UUID()
    public var source: StatementSource
    public var fileName: String
    public var transactions: [ImportedTransaction]
    public var warnings: [String]
    public var totalRows: Int

    public init(
        source: StatementSource,
        fileName: String,
        transactions: [ImportedTransaction],
        warnings: [String],
        totalRows: Int
    ) {
        self.source = source
        self.fileName = fileName
        self.transactions = transactions
        self.warnings = warnings
        self.totalRows = totalRows
    }
}

// MARK: - Errors

public enum StatementImportError: Error, LocalizedError {
    case unreadableText
    case unrecognizedFormat
    case noTransactions

    public var errorDescription: String? {
        switch self {
        case .unreadableText:
            "无法读取文件内容，请确认文件未损坏。"
        case .unrecognizedFormat:
            "无法识别该账单格式。请确认是微信支付或支付宝导出的 CSV 账单文件。"
        case .noTransactions:
            "文件中没有找到可导入的交易记录。"
        }
    }
}

// MARK: - Importer

public enum StatementImporter {
    public static func parse(data: Data, fileName: String = "") throws -> StatementParseResult {
        guard let rawText = decodeText(data) else {
            throw StatementImportError.unreadableText
        }
        let text = rawText.hasPrefix("\u{FEFF}") ? String(rawText.dropFirst()) : rawText
        let rows = CSV.rows(from: text)

        guard let headerIndex = findHeaderIndex(in: rows) else {
            throw StatementImportError.unrecognizedFormat
        }

        let header = rows[headerIndex].map(normalize)
        let fullText = text.lowercased()
        let source = detectSource(header: header, fullText: fullText, fileName: fileName)

        guard let timeIndex = firstIndex(in: header, candidates: ["交易时间", "交易创建时间", "付款时间"]),
              let amountIndex = firstIndex(in: header, candidates: ["金额(元)", "金额（元）", "金额"], contains: true),
              let directionIndex = firstIndex(in: header, candidates: ["收/支", "收支"], contains: true) else {
            throw StatementImportError.unrecognizedFormat
        }

        let typeIndex = firstIndex(in: header, candidates: ["交易类型", "类型"], contains: true)
        let counterpartyIndex = firstIndex(in: header, candidates: ["交易对方"], contains: true)
        let productIndex = firstIndex(in: header, candidates: ["商品", "商品名称"], contains: true)
        let statusIndex = firstIndex(in: header, candidates: ["当前状态", "交易状态"], contains: true)
        let methodIndex = firstIndex(in: header, candidates: ["支付方式"], contains: true)
        let noteIndex = firstIndex(in: header, candidates: ["备注"], contains: true)
        let txIDIndex = firstIndex(in: header, candidates: ["交易单号", "交易号"], contains: true)

        let dateFormatters = makeDateFormatters()
        var transactions: [ImportedTransaction] = []
        var warnings: [String] = []
        var seenExternalIDs = Set<String>()
        var totalRows = 0

        for rowIndex in (headerIndex + 1)..<rows.count {
            let row = rows[rowIndex]
            let trimmed = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard trimmed.contains(where: { !$0.isEmpty }) else { continue }
            guard trimmed.count > max(timeIndex, amountIndex, directionIndex) else { continue }
            if isSeparatorRow(trimmed) || isSummaryRow(trimmed) { continue }

            totalRows += 1
            let lineNumber = rowIndex + 1

            let dateText = trimmed[timeIndex]
            guard let occurredAt = parseDate(dateText, formatters: dateFormatters) else {
                warnings.append("第 \(lineNumber) 行日期无法识别：\(dateText)")
                continue
            }

            let amountText = trimmed[amountIndex]
            guard let amountMinor = parseAmount(amountText), amountMinor > 0 else {
                warnings.append("第 \(lineNumber) 行金额无法识别：\(amountText)")
                continue
            }

            let direction = trimmed[directionIndex]
            let type = value(at: typeIndex, in: trimmed)
            let status = value(at: statusIndex, in: trimmed)
            let counterparty = value(at: counterpartyIndex, in: trimmed)
            let product = value(at: productIndex, in: trimmed)
            let note = value(at: noteIndex, in: trimmed)
            let method = value(at: methodIndex, in: trimmed)

            let isRefund = type.contains("退款") || status.contains("退款")
            let isTransfer = type.contains("转账") || type.contains("亲属卡")

            var kind: TransactionKind
            if isRefund {
                kind = .income
            } else if direction.contains("支出") {
                kind = .expense
            } else if direction.contains("收入") {
                kind = .income
            } else {
                if isTransfer {
                    warnings.append("第 \(lineNumber) 行转账为「不计收支」，未导入")
                } else {
                    warnings.append("第 \(lineNumber) 行收/支字段无法识别：\(direction)")
                }
                continue
            }

            let categoryRaw: String
            if isRefund {
                categoryRaw = "退款"
            } else if isTransfer {
                categoryRaw = "转账"
            } else {
                categoryRaw = inferCategory(
                    type: type,
                    counterparty: counterparty,
                    product: product,
                    note: note
                ).rawValue
            }

            let externalID = makeExternalID(
                source: source,
                txID: value(at: txIDIndex, in: trimmed),
                occurredAt: occurredAt,
                amountMinor: amountMinor,
                kind: kind,
                counterparty: counterparty,
                product: product,
                note: note
            )

            guard seenExternalIDs.insert(externalID).inserted else {
                warnings.append("第 \(lineNumber) 行与文件内其他记录重复，已跳过")
                continue
            }

            let channel = inferChannel(source: source, method: method)
            let combinedNote = [product, note].filter { !$0.isEmpty }.joined(separator: " · ")

            transactions.append(
                ImportedTransaction(
                    id: externalID,
                    source: source,
                    occurredAt: occurredAt,
                    kind: kind,
                    amountMinor: amountMinor,
                    categoryRaw: categoryRaw,
                    channel: channel,
                    merchant: counterparty,
                    note: combinedNote,
                    externalID: externalID,
                    isRefund: isRefund,
                    isTransfer: isTransfer
                )
            )
        }

        guard !transactions.isEmpty else {
            throw StatementImportError.noTransactions
        }

        if warnings.count > 20 {
            warnings = Array(warnings.prefix(20)) + ["……另有 \(warnings.count - 20) 条提示未显示"]
        }

        return StatementParseResult(
            source: source,
            fileName: fileName,
            transactions: transactions,
            warnings: warnings,
            totalRows: totalRows
        )
    }

    // MARK: Text decoding

    public static func decodeText(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .utf16) {
            return text
        }
        if let text = decodeGB18030(data) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return nil
    }

    private static func decodeGB18030(_ data: Data) -> String? {
        let encoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        return String(data: data, encoding: String.Encoding(rawValue: encoding))
    }

    // MARK: Detection

    private static func findHeaderIndex(in rows: [[String]]) -> Int? {
        for (index, row) in rows.enumerated() {
            let joined = row.map(normalize).joined(separator: "|")
            let hasTime = joined.contains("交易时间") || joined.contains("交易创建时间") || joined.contains("付款时间")
            let hasAmount = joined.contains("金额")
            let hasDirection = joined.contains("收/支") || joined.contains("收支")
            if hasTime && hasAmount && hasDirection {
                return index
            }
        }
        return nil
    }

    private static func detectSource(header: [String], fullText: String, fileName: String) -> StatementSource {
        let joined = header.joined(separator: "|")
        if fullText.contains("微信") || joined.contains("交易单号") || joined.contains("支付方式") || fileName.contains("微信") {
            return .wechat
        }
        if fullText.contains("支付宝") || joined.contains("交易号") || joined.contains("商家订单号") || fileName.contains("支付宝") {
            return .alipay
        }
        return .wechat
    }

    // MARK: Row helpers

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{3000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstIndex(in header: [String], candidates: [String], contains: Bool = false) -> Int? {
        for (index, value) in header.enumerated() {
            for candidate in candidates {
                if contains ? value.contains(candidate) : value == candidate {
                    return index
                }
            }
        }
        return nil
    }

    private static func value(at index: Int?, in row: [String]) -> String {
        guard let index, row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSeparatorRow(_ row: [String]) -> Bool {
        let joined = row.joined()
        return joined.filter { $0 != "-" && $0 != " " }.isEmpty
    }

    private static func isSummaryRow(_ row: [String]) -> Bool {
        let joined = row.joined()
        return joined.contains("共") && joined.contains("笔")
    }

    // MARK: Parsing helpers

    private static func makeDateFormatters() -> [DateFormatter] {
        ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd", "yyyy/MM/dd"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            return formatter
        }
    }

    private static func parseDate(_ text: String, formatters: [DateFormatter]) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private static func parseAmount(_ text: String) -> Int? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "¥", with: "")
        cleaned = cleaned.replacingOccurrences(of: "￥", with: "")
        cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        cleaned = cleaned.replacingOccurrences(of: "＋", with: "+")
        cleaned = cleaned.replacingOccurrences(of: "－", with: "-")
        if cleaned.hasPrefix("+") || cleaned.hasPrefix("-") {
            cleaned = String(cleaned.dropFirst())
        }
        return MoneyParser.minorUnits(from: cleaned, currencyCode: "CNY").map(abs)
    }

    private static func inferChannel(source: StatementSource, method: String) -> PaymentChannel {
        if source == .alipay {
            return .alipay
        }
        if method.contains("零钱") || method.contains("微信") {
            return .wechat
        }
        if method.contains("信用") || method.contains("花呗") {
            return .creditCard
        }
        if method.contains("银行") || method.contains("卡") {
            return .bankCard
        }
        return .wechat
    }

    private static func inferCategory(type: String, counterparty: String, product: String, note: String) -> BuiltInCategory {
        let haystack = [type, counterparty, product, note].joined(separator: " ").lowercased()

        let rules: [(BuiltInCategory, [String])] = [
            (.dining, ["餐", "饭", "咖啡", "奶茶", "外卖", "美团", "饿了么", "麦当劳", "肯德基", "便利店", "星巴克"]),
            (.transport, ["地铁", "公交", "打车", "滴滴", "出租", "加油", "停车", "火车", "高铁", "机票", "航空"]),
            (.shopping, ["超市", "淘宝", "天猫", "京东", "拼多多", "商场", "购物", "盒马", "山姆"]),
            (.study, ["书", "教育", "课程", "培训", "学费", "考试", "文具"]),
            (.entertainment, ["电影", "游戏", "视频", "音乐", "ktv", "娱乐", "演出"]),
            (.medical, ["医院", "药", "医疗", "体检", "诊所"]),
            (.housing, ["房租", "物业", "水费", "电费", "燃气", "宽带"]),
            (.other, [])
        ]

        for (category, keywords) in rules {
            if keywords.contains(where: { haystack.contains($0) }) {
                return category
            }
        }
        return .other
    }

    private static func makeExternalID(
        source: StatementSource,
        txID: String,
        occurredAt: Date,
        amountMinor: Int,
        kind: TransactionKind,
        counterparty: String,
        product: String,
        note: String
    ) -> String {
        let trimmedID = txID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedID.isEmpty, trimmedID != "/" {
            return "\(source.rawValue):\(trimmedID)"
        }

        let fingerprint = [
            source.rawValue,
            String(occurredAt.timeIntervalSince1970),
            String(amountMinor),
            kind.rawValue,
            counterparty,
            product,
            note
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(fingerprint.utf8))
        return "\(source.rawValue):fp:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
