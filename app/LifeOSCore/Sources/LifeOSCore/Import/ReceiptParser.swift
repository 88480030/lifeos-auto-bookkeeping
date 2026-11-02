import CryptoKit
import Foundation

public struct ReceiptAmountCandidate: Identifiable, Hashable, Sendable {
    public let amountMinor: Int
    public let currencyCode: String
    public let sourceText: String
    public let isPreferred: Bool

    public var id: String { "\(currencyCode):\(amountMinor)" }
}

/// OCR suggestions. Automatic recording is allowed only when permitsAutomaticRecording is true.
public struct ReceiptParseResult: Sendable {
    public let amountCandidates: [ReceiptAmountCandidate]
    public let suggestedAmount: ReceiptAmountCandidate?
    public let merchant: String?
    public let occurredAt: Date?
    public let hasExplicitTime: Bool
    public let channel: PaymentChannel?
    public let kind: TransactionKind
    public let categoryRaw: String
    public let transactionID: String?
    public let externalID: String
    public let warnings: [String]
    public let permitsAutomaticRecording: Bool
    public let recipientConfirmationPending: Bool
}

public enum ReceiptParser {
    private static func isCompactMerchant(_ text: String) -> Bool {
        firstMatch(#"^[\p{Han}A-Za-z0-9（）()·]{2,60}(?:有限公司|有限责任公司|餐厅|餐馆|便利店|超市)$"#, in: text) != nil
    }
    private struct ScoredAmount {
        let amountMinor: Int
        let currencyCode: String
        let sourceText: String
        let score: Int
        var id: String { "\(currencyCode):\(amountMinor)" }
    }

    public static func parse(
        lines: [String],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> ReceiptParseResult {
        let cleaned = lines.map(normalizeLine).filter { !$0.isEmpty }
        let fullText = cleaned.joined(separator: "\n")
        let channel = detectChannel(fullText)
        let refundCompleted = containsAny(fullText, ["退款成功", "退款到账", "已全额退款", "已部分退款", "已退款"])
        let income = refundCompleted || containsAny(fullText, ["收款成功", "收钱到账", "到账成功", "收入金额", "转账收入"])
            || firstMatch(#"收[ /]?支\s*[:：]?\s*收入"#, in: fullText) != nil
        let kind: TransactionKind = income ? .income : .expense
        let incomplete = containsAny(fullText, ["支付失败", "付款失败", "交易失败", "未支付", "未付款", "未交易成功", "交易未成功", "未扣款", "未成功", "交易关闭", "交易取消", "已取消", "已关闭", "等待付款", "待付款", "待支付", "支付中", "扣款失败", "扣款中", "待扣款", "payment failed", "payment pending", "pending payment", "payment cancelled", "payment canceled", "退款处理中", "退款申请中", "退款中", "已撤销", "已退还", "已退回"])

        var warnings: [String] = []
        if cleaned.isEmpty { warnings.append("没有识别到可用文字，请换一张清晰的付款详情截图。") }
        if refundCompleted { warnings.append("识别到退款到账，已建议收入；请确认退款金额，避免重复记录原支出。") }
        else if income { warnings.append("识别到收款或收入信息，请确认收支方向。") }
        if incomplete { warnings.append("截图可能不是已完成交易，请确认实际付款或到账状态。") }
        if fullText.localizedCaseInsensitiveContains("微信") && fullText.localizedCaseInsensitiveContains("支付宝") {
            warnings.append("截图包含多个支付平台，请确认支付方式。")
        }

        let explicitSuccess = containsAny(fullText, ["自动扣款成功", "支付成功", "付款成功", "交易成功", "支付完成", "交易完成", "收款成功", "收钱到账", "到账成功", "退款成功", "退款到账", "已全额退款", "已部分退款", "已退款"])
            || firstMatch(#"交易状态\s*[:：]?\s*成功"#, in: fullText) != nil
            || cleaned.indices.contains { isPaymentSuccess(at: $0, in: cleaned) }
        let contextCurrency = detectCurrency(fullText)
        // Apple Pay can use either RMB or yen; the shared ¥ glyph alone does
        // not identify which currency was charged.
        let applePayYenAmbiguous = containsAny(fullText, ["Apple Pay"]) && fullText.contains("¥")
            && !containsAny(fullText, ["CNY", "RMB", "人民币", "JPY", "日元", "円"])
        // A submitted transfer can await the recipient's acceptance, while a
        // system overlay hides its success header. Admit only this exact compact
        // page shape, and preserve that the recipient has not confirmed yet.
        let pendingRecipientTransfer = !explicitSuccess && !incomplete && !refundCompleted && contextCurrency == nil
            && cleaned.contains("完成") && cleaned.enumerated().contains { index, line in
                guard index + 1 < cleaned.count else { return false }
                return firstMatch(#"^待\s*.{1,40}?\s*确认收款$"#, in: line) != nil
                    && firstMatch(#"^[·•・.]\s*[0-9]+\.[0-9]{2}$"#, in: cleaned[index + 1]) != nil
            }
        let completed = explicitSuccess || pendingRecipientTransfer
        var scored: [String: ScoredAmount] = [:]
        var invalidPrecision = false
        var usedBareDollar = false
        var signedBillMerchant: String?
        var automaticDeductionAmountDetected = false
        var genericSignedAmountDetected = false
        var successDotAmountDetected = false
        let signedBillPattern = #"^[-−–]\s*[0-9]+\.[0-9]{2}$"#
        let signedBillCount = cleaned.filter { firstMatch(signedBillPattern, in: $0) != nil }.count
        for (index, line) in cleaned.enumerated() {
            let previous = index > 0 ? cleaned[index - 1] : ""
            let priorCurrency = detectCurrency(previous)
            let currencyOnlyPrevious = firstMatch(#"^(?:CNY|RMB|USD|US\$|HKD|HK\$|JPY|JP¥|EUR|GBP|KRW|SGD|S\$|AUD|A\$|CAD|C\$|人民币|日元|美元|港币|¥|\$|€|£|₩)$"#, in: previous) != nil
            let standaloneNumber = firstMatch(#"^[+-]?\s*[0-9,]+(?:\.[0-9]{1,3})?$"#, in: line) != nil
            // Vision sometimes reads the isolated yuan glyph as a middle dot on
            // WeChat's compact Chinese transfer-success page. Only recover this
            // exact layout, with a recipient directly above and two decimal places.
            let compactTransferAmount = completed && !incomplete
                && firstMatch(#"^待\s*.{1,40}?\s*确认收款$"#, in: previous) != nil
                && firstMatch(#"^[·•・.]\s*[0-9]+\.[0-9]{2}$"#, in: line) != nil
                && contextCurrency == nil
                && cleaned.filter { firstMatch(#"^[·•・.]\s*[0-9]+\.[0-9]{2}$"#, in: $0) != nil }.count == 1
            // In compact payment-success screens Vision may replace the yuan
            // glyph with a middle dot. Require payment and recipient fields,
            // an adjacent explicit paid status, and a single decimal amount.
            let compactCompanyAmount = index > 1 && index + 1 < cleaned.count
                && firstMatch(#"^(?:支付成功|付款成功|交易成功)$"#, in: cleaned[index - 2]) != nil
                && isCompactMerchant(previous)
                && cleaned.contains("完成")
            let successDotAmount = explicitSuccess && !incomplete && !income
                && (contextCurrency == nil || contextCurrency == "CNY")
                && (compactCompanyAmount || (containsAny(fullText, ["付款方式", "支付方式"])
                && containsAny(fullText, ["收款方", "收款人", "交易对方"])
                && index > 0 && isPaymentSuccess(at: index - 1, in: cleaned)))
                && firstMatch(#"^[·•・.]\s*[0-9]+\.[0-9]{2}$"#, in: line) != nil
                && cleaned.filter { firstMatch(#"^[·•・.]\s*[0-9]+\.[0-9]{2}$"#, in: $0) != nil }.count == 1
            if successDotAmount { successDotAmountDetected = true }
            // A WeChat bill can show a bare negative amount directly above its
            // payment-success status. Require the bill's payment provider and a
            // single signed amount; never use status-bar numbers as money.
            let signedSuccessfulBill = !incomplete && !income && signedBillCount == 1
                && (contextCurrency == nil || contextCurrency == "CNY")
                && containsAny(fullText, ["财付通支付科技有限公司", "财付通支付科技"])
                && index + 1 < cleaned.count
                && firstMatch(signedBillPattern, in: line) != nil
                && firstMatch(#"^当前状态\s*[:：]?\s*支付成功$"#, in: cleaned[index + 1]) != nil
            // Alipay's renewal bill displays a negative amount immediately
            // before its explicit successful deduction status, without a yuan glyph.
            // Require the observed payment-time and renewal fields as context.
            let signedAutomaticDeduction = !incomplete && !income && signedBillCount == 1
                && (contextCurrency == nil || contextCurrency == "CNY")
                && containsAny(fullText, ["管理自动续费"]) && containsAny(fullText, ["支付时间"])
                && index + 1 < cleaned.count
                && firstMatch(signedBillPattern, in: line) != nil
                && firstMatch(#"^自动扣款成功$"#, in: cleaned[index + 1]) != nil
            // A single negative amount adjacent to an explicit paid status is
            // common on mainland payment and merchant receipts. Brand text is
            // only context for currency, never evidence of payment by itself.
            let isMainlandPaymentContext = containsAny(fullText, ["支付宝", "微信", "云闪付", "美团", "京东", "淘宝", "抖音", "拼多多"])
            let adjacentSuccess = (index > 0 && isPaymentSuccess(at: index - 1, in: cleaned))
                || (index > 1 && isPaymentSuccess(at: index - 2, in: cleaned)
                    && firstMatch(#"^(?:交易状态|支付状态|付款状态)$"#, in: cleaned[index - 2]) != nil)
                || (index + 1 < cleaned.count && isPaymentSuccess(at: index + 1, in: cleaned))
            let signedGenericBill = !incomplete && !income && signedBillCount == 1
                && isMainlandPaymentContext && (contextCurrency == nil || contextCurrency == "CNY")
                && firstMatch(signedBillPattern, in: line) != nil && adjacentSuccess
            if signedAutomaticDeduction { automaticDeductionAmountDetected = true }
            if signedGenericBill { genericSignedAmountDetected = true }
            if (signedSuccessfulBill || signedAutomaticDeduction || signedGenericBill) && !previous.isEmpty && previous.count <= 100
                && !containsAny(previous, ["账单", "交易单号", "支付方式", "交易时间", "支付时间"])
                && !isStandalonePaymentSuccess(previous)
                && firstMatch(#"^(?:支付宝|微信支付|微信|云闪付|银行卡|Apple Pay|美团|京东|淘宝|抖音|拼多多)$"#, in: previous) == nil {
                signedBillMerchant = previous.trimmingCharacters(in: CharacterSet(charactersIn: " >›〉→"))
            }
            let amountLine = currencyOnlyPrevious && standaloneNumber ? previous + " " + line
                : (compactTransferAmount || successDotAmount) ? "CNY " + String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                : (signedSuccessfulBill || signedAutomaticDeduction || signedGenericBill) ? line.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "–", with: "-")
                : line
            let contextLine = (signedSuccessfulBill || signedAutomaticDeduction || signedGenericBill) ? "支付金额" : (currencyOnlyPrevious && standaloneNumber && index > 1 ? cleaned[index - 2] : previous)
            let strongLineCurrency = detectCurrency(line.replacingOccurrences(of: "¥", with: ""))
            let amounts = extractAmounts(line: amountLine, previous: contextLine, kind: kind,
                                         contextCurrency: strongLineCurrency ?? priorCurrency ?? contextCurrency,
                                         invalidPrecision: &invalidPrecision,
                                         usedBareDollar: &usedBareDollar)
            for amount in amounts {
                if let old = scored[amount.id], old.score >= amount.score { continue }
                scored[amount.id] = amount
            }
        }
        let ordered = scored.values.sorted {
            $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score
        }
        let bestScore = ordered.first?.score ?? 0
        let best = ordered.filter { $0.score == bestScore }
        // Compact success screens place an unlabelled recipient between the status
        // and the only currency-marked amount. Do not require adjacent labels.
        let soleCompletedAmount = completed && ordered.count == 1 && bestScore >= 30
        let preferredID = !incomplete && (bestScore >= 90 || soleCompletedAmount) && best.count == 1 ? best.first?.id : nil
        let candidates = ordered.map {
            ReceiptAmountCandidate(amountMinor: $0.amountMinor, currencyCode: $0.currencyCode,
                                   sourceText: $0.sourceText, isPreferred: $0.id == preferredID)
        }
        if candidates.isEmpty { warnings.append("没有可靠的金额候选，请手动填写金额。") }
        else if preferredID == nil { warnings.append("金额尚不能确定，请从候选金额中选择或手动填写。") }
        if invalidPrecision { warnings.append("部分金额不符合币种小数位要求，未自动采用，请核对原图。") }
        if usedBareDollar { warnings.append("单独的 $ 符号按美元识别，请确认是否为其他币种。") }

        let merchant = cleaned.compactMap { captureGroups(#"^待\s*(.{1,40}?)\s*确认收款$"#, in: $0)?.first }.first
            ?? labeledValue(in: cleaned, labels: ["商户全称", "收款商户", "商户名称", "商家名称", "收款方", "交易对方", "付款给", "收款人", "商家"])
            ?? signedBillMerchant
            ?? (explicitSuccess && !incomplete && candidates.count == 1 ? cleaned.indices.compactMap { index -> String? in
                guard index > 0, index + 1 < cleaned.count,
                      cleaned[..<index].contains(where: { containsAny($0, ["支付成功", "付款成功", "交易成功"]) }),
                      firstMatch(#"^[¥￥·•・.]\s*[0-9,]+\.[0-9]{2}$"#, in: cleaned[index + 1]) != nil,
                      isCompactMerchant(cleaned[index]) else { return nil }
                return cleaned[index]
            }.first : nil)
        if merchant == nil { warnings.append("未识别商家，请核对后填写。") }
        let date = extractDate(from: cleaned, referenceDate: referenceDate, calendar: calendar)
        if date.date == nil { warnings.append("未识别交易日期，请核对后填写。") }
        else if !date.hasTime { warnings.append("只识别到日期，没有交易时间，请核对时间。") }

        let transactionID = labeledTransactionID(in: cleaned)
        let digest = SHA256.hash(data: Data(fullText.utf8)).map { String(format: "%02x", $0) }.joined()
        let externalID: String
        if let channel, let transactionID, channel == .wechat || channel == .alipay {
            externalID = "receipt:\(channel.rawValue):tx:\(transactionID)"
        } else {
            externalID = "receipt:sha256:\(digest)"
        }
        let product = labeledValue(in: cleaned, labels: ["商品说明", "商品名称", "商品", "付款说明"])
        return ReceiptParseResult(
            amountCandidates: candidates, suggestedAmount: candidates.first(where: \.isPreferred),
            merchant: merchant, occurredAt: date.date, hasExplicitTime: date.hasTime,
            channel: channel, kind: kind,
            categoryRaw: inferCategory(merchant: merchant, product: product).rawValue,
            transactionID: transactionID, externalID: externalID, warnings: warnings,
            permitsAutomaticRecording: completed && preferredID != nil && signedBillCount <= 1 && (candidates.count == 1 || bestScore >= 100) && (!(automaticDeductionAmountDetected || genericSignedAmountDetected || successDotAmountDetected) || candidates.count == 1) && !invalidPrecision && !usedBareDollar && !applePayYenAmbiguous
                && !(fullText.contains("$") && !containsAny(fullText, ["USD", "US$", "美元", "HKD", "HK$", "港币", "SGD", "S$", "AUD", "A$", "CAD", "C$"]))
                && !(fullText.contains("微信") && fullText.contains("支付宝")),
            recipientConfirmationPending: pendingRecipientTransfer
        )
    }

    private static let moneyPattern = #"(?<![A-Za-z0-9.])(?:(CNY|RMB|USD|US\$|HKD|HK\$|JPY|JP¥|EUR|GBP|KRW|SGD|S\$|AUD|A\$|CAD|C\$|人民币|日元|美元|港币|¥|\$|€|£|₩)\s*)?([+-]?\s*(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]{1,3})?)\s*(元|円|日元|人民币|美元|港币|CNY|USD|HKD|JPY|EUR)?(?![A-Za-z0-9.])"#

    private static func extractAmounts(
        line: String, previous: String, kind: TransactionKind, contextCurrency: String?,
        invalidPrecision: inout Bool, usedBareDollar: inout Bool
    ) -> [ScoredAmount] {
        let metadata = ["交易单号", "交易号", "订单号", "流水号", "手机号", "手机号码", "银行卡号", "账户余额", "剩余余额", "可用余额", "优惠", "红包", "积分", "折扣", "原价", "商品总价", "原金额", "服务费", "手续费", "汇率"]
        let actual = ["实付", "实际付款", "实际支付", "已付金额", "支付金额", "付款金额", "交易金额", "支出金额", "消费金额", "实际扣款", "扣款金额"]
        let incoming = ["退款金额", "退款到账", "到账金额", "收入金额", "收款金额"]
        let expectedLabels = kind == .income ? incoming : actual
        let lineHasActual = containsAny(line, expectedLabels)
        if containsAny(line, metadata) && !lineHasActual { return [] }
        if !lineHasActual && firstMatch(#"[0-9]{4}[-/.年][0-9]{1,2}[-/.月][0-9]{1,2}"#, in: line) != nil { return [] }
        if firstMatch(#"^\s*[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?\s*$"#, in: line) != nil { return [] }
        guard let expression = try? NSRegularExpression(pattern: moneyPattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let matches = expression.matches(in: line, range: range)
        return matches.compactMap { match in
            func group(_ number: Int) -> String {
                guard let range = Range(match.range(at: number), in: line) else { return "" }
                return String(line[range])
            }
            let prefix = group(1), suffix = group(3)
            let numeric = group(2).replacingOccurrences(of: " ", with: "")
            let hasCurrency = !prefix.isEmpty || !suffix.isEmpty
            let sameLineScore = containsAny(line, expectedLabels) ? 110 : containsAny(line, ["金额", "总计", "合计"]) ? 75 : 0
            let previousScore = containsAny(previous, expectedLabels) ? 100
                : containsAny(previous, ["支付成功", "付款成功", "收款成功", "交易成功", "退款成功"]) ? 95
                : containsAny(previous, ["金额", "总计", "合计"]) ? 70 : 0
            let isStandalone = firstMatch(#"^\s*[+-]?\s*[0-9,]+(?:\.[0-9]{1,3})?\s*$"#, in: line) != nil
            guard hasCurrency || (isStandalone && previousScore > 0) || sameLineScore > 0 else { return nil }
            if !hasCurrency && numeric.filter(\.isNumber).count > 9 { return nil }
            // A balance or discount in a combined OCR line is not another payment amount.
            if let amountRange = Range(match.range, in: line) {
                let before = String(line[..<amountRange.lowerBound])
                let excludedEnd = metadata.compactMap { before.range(of: $0, options: .backwards)?.upperBound }.max()
                let actualEnd = expectedLabels.compactMap { before.range(of: $0, options: .backwards)?.upperBound }.max()
                if let excludedEnd, actualEnd == nil || excludedEnd > actualEnd! { return nil }
            }
            let code = currencyCode(marker: prefix, suffix: suffix, context: contextCurrency)
            if prefix == "$" && contextCurrency == nil { usedBareDollar = true }
            let amountText = numeric.replacingOccurrences(of: ",", with: "")
            guard let signed = MoneyParser.minorUnits(from: amountText, currencyCode: code), signed != Int.min else {
                invalidPrecision = true
                return nil
            }
            let minor = abs(signed)
            guard minor > 0 else { return nil }
            let score = max(sameLineScore, previousScore, hasCurrency ? 30 : 0)
            return ScoredAmount(amountMinor: minor, currencyCode: code, sourceText: line, score: score)
        }
    }

    private static func currencyCode(marker: String, suffix: String, context: String?) -> String {
        let value = marker.isEmpty ? suffix : marker
        if value == "¥" { return context == "JPY" ? "JPY" : "CNY" }
        if value == "元" { return "CNY" }
        return detectCurrency(value) ?? context ?? "CNY"
    }

    private static func detectCurrency(_ text: String) -> String? {
        let values: [(String, [String])] = [
            ("HKD", ["HKD", "HK$", "港币"]), ("JPY", ["JPY", "JP¥", "日元", "円"]),
            ("SGD", ["SGD", "S$"]), ("AUD", ["AUD", "A$"]), ("CAD", ["CAD", "C$"]),
            ("USD", ["USD", "US$", "美元"]), ("EUR", ["EUR", "€"]),
            ("GBP", ["GBP", "£"]), ("KRW", ["KRW", "₩"]),
            ("CNY", ["CNY", "RMB", "人民币", "¥"])
        ]
        for (code, markers) in values where containsAny(text, markers) { return code }
        return text.contains("$") ? "USD" : nil
    }

    private static func detectChannel(_ text: String) -> PaymentChannel? {
        let wechat = containsAny(text, ["微信", "WeChat", "Weixin"])
        let alipay = containsAny(text, ["支付宝", "Alipay"])
        if wechat && !alipay { return .wechat }
        if alipay && !wechat { return .alipay }
        return nil
    }

    private static func labeledValue(in lines: [String], labels: [String]) -> String? {
        for label in labels {
            for (index, line) in lines.enumerated() {
                guard let range = line.range(of: label) else { continue }
                let trailing = String(line[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " :：-"))
                let value = trailing.isEmpty && index + 1 < lines.count ? lines[index + 1] : trailing
                guard !value.isEmpty, value.count <= 100,
                      !labels.contains(value),
                      !containsAny(value, ["交易时间", "支付时间", "付款时间", "订单号", "交易单号", "支付方式", "实际付款", "查看账单", "账单详情"]),
                      firstMatch(#"^[0-9,.¥$+\- :]+$"#, in: value) == nil else { continue }
                return value
            }
        }
        return nil
    }

    private static func labeledTransactionID(in lines: [String]) -> String? {
        let labels = ["微信支付订单号", "支付交易号", "交易单号", "交易流水号", "交易号"]
        for (index, line) in lines.enumerated() {
            guard !containsAny(line, ["商户订单", "商家订单"]) else { continue }
            for label in labels {
                guard let range = line.range(of: label) else { continue }
                let trailing = String(line[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " :："))
                let raw = trailing.isEmpty && index + 1 < lines.count ? lines[index + 1] : trailing
                let compact = raw.replacingOccurrences(of: " ", with: "")
                if firstMatch(#"^[A-Za-z0-9]{6,64}$"#, in: compact) != nil,
                   compact.contains(where: \.isNumber) { return compact }
            }
        }
        return nil
    }

    private static func extractDate(from lines: [String], referenceDate: Date, calendar: Calendar) -> (date: Date?, hasTime: Bool) {
        let labels = ["付款时间", "支付时间", "交易时间", "到账时间", "退款时间", "交易创建时间"]
        let normalizedLines = lines.enumerated().map { index, line in
            if index + 1 < lines.count,
               firstMatch(#"[0-9]{4}[-/.年][0-9]{1,2}[-/.月][0-9]{1,2}日?$"#, in: line) != nil,
               firstMatch(#"^[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?$"#, in: lines[index + 1]) != nil {
                return line + " " + lines[index + 1]
            }
            return line
        }
        var ordered: [String] = []
        for (index, line) in normalizedLines.enumerated() where containsAny(line, labels) {
            ordered.append(line)
            if index + 1 < normalizedLines.count { ordered.append(normalizedLines[index + 1]) }
        }
        ordered.append(contentsOf: normalizedLines.filter { !containsAny($0, ["有效期", "优惠券", "到期", "生效"]) })
        let pattern = #"([0-9]{4})[-/.年]([0-9]{1,2})[-/.月]([0-9]{1,2})日?(?:[ T\s]+([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?)?"#
        for text in ordered {
            if let groups = captureGroups(pattern, in: text), groups.count == 6,
               let year = Int(groups[0]), let month = Int(groups[1]), let day = Int(groups[2]),
               (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day) {
                let hasTime = !groups[3].isEmpty
                let hour = Int(groups[3]) ?? 0, minute = Int(groups[4]) ?? 0, second = Int(groups[5]) ?? 0
                guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { continue }
                var components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
                components.timeZone = calendar.timeZone
                if let date = calendar.date(from: components) {
                    let actual = calendar.dateComponents([.year, .month, .day], from: date)
                    if actual.year == year && actual.month == month && actual.day == day { return (date, hasTime) }
                }
            }
            if containsAny(text, labels), let relative = firstMatch(#"(今天|昨天)\s*([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?"#, in: text),
               let groups = captureGroups(#"(今天|昨天)\s*([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?"#, in: relative), groups.count == 4 {
                let day = calendar.date(byAdding: .day, value: groups[0] == "昨天" ? -1 : 0, to: referenceDate) ?? referenceDate
                let hour = Int(groups[1]) ?? -1, minute = Int(groups[2]) ?? -1, second = Int(groups[3]) ?? 0
                if (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second),
                   let date = calendar.date(bySettingHour: hour, minute: minute, second: second, of: day) { return (date, true) }
            }
        }
        return (nil, false)
    }

    private static func inferCategory(merchant: String?, product: String?) -> BuiltInCategory {
        let mapping: [(BuiltInCategory, [String])] = [
            (.transport, ["滴滴", "打车", "出租", "地铁", "公交", "车费", "停车", "铁路", "机票"]),
            (.medical, ["药店", "医院", "诊所", "挂号", "医药"]),
            (.housing, ["房租", "物业", "水费", "电费", "燃气"]),
            (.study, ["书店", "书籍", "课程", "培训", "学费"]),
            (.dining, ["餐", "饭", "咖啡", "奶茶", "饮品", "麦当劳", "肯德基", "星巴克", "瑞幸", "松屋"]),
            (.entertainment, ["电影", "游戏", "影院", "演出"]),
            (.shopping, ["超市", "便利店", "商场", "淘宝", "京东", "日用品"])
        ]
        for value in [merchant, product].compactMap({ $0 }) {
            for (category, keywords) in mapping where containsAny(value, keywords) { return category }
        }
        return .other
    }

    private static func normalizeLine(_ line: String) -> String {
        (line.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? line)
            .replacingOccurrences(of: "￥", with: "¥")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Bare order completion and isolated "成功" are not payment confirmation.
    private static func isStandalonePaymentSuccess(_ line: String) -> Bool {
        firstMatch(#"^(?:(?:当前状态|交易状态|支付状态|付款状态|订单状态)\s*[:：]?\s*)?(?:支付成功|付款成功|交易成功|扣款成功|自动扣款成功|支付完成|交易完成|已支付|已付款|Payment Successful|Payment Complete|Transaction Successful)$"#, in: line) != nil
            || firstMatch(#"^(?:交易状态|支付状态|付款状态)\s*[:：]?\s*成功$"#, in: line) != nil
    }

    private static func isPaymentSuccess(at index: Int, in lines: [String]) -> Bool {
        guard lines.indices.contains(index) else { return false }
        if isStandalonePaymentSuccess(lines[index]) { return true }
        return index + 1 < lines.count
            && firstMatch(#"^(?:交易状态|支付状态|付款状态)\s*[:：]?$"#, in: lines[index]) != nil
            && firstMatch(#"^成功$"#, in: lines[index + 1]) != nil
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.range(of: $0, options: .caseInsensitive) != nil }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }

    private static func captureGroups(_ pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
