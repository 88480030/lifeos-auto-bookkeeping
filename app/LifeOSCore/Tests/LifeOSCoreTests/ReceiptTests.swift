import Foundation
import SwiftData
import Testing
@testable import LifeOSCore

private func receiptCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}

private func receiptDate(_ day: Int = 27, hour: Int = 12, minute: Int = 5) -> Date {
    receiptCalendar().date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@Test func receiptActualAmountWinsOverOriginalPriceDiscountAndBalance() throws {
    let result = ReceiptParser.parse(lines: [
        "支付宝", "支付成功", "实际付款 ¥34.50", "原价 ¥40.00", "优惠 ¥5.50", "账户余额 ¥990.00",
        "商户全称", "瑞幸咖啡", "付款时间", "2026-10-27 12:05:00", "交易号", "2026102722000001234567890"
    ], calendar: receiptCalendar())
    #expect(result.suggestedAmount?.amountMinor == 3450)
    #expect(result.suggestedAmount?.currencyCode == "CNY")
    #expect(result.amountCandidates.count == 1)
    #expect(result.merchant == "瑞幸咖啡")
    #expect(result.categoryRaw == BuiltInCategory.dining.rawValue)
    #expect(result.channel == .alipay)
    #expect(result.occurredAt == receiptDate())
    #expect(result.hasExplicitTime)
    #expect(result.externalID == "receipt:alipay:tx:2026102722000001234567890")
}

@Test func receiptSupportsAmountSplitFromCurrencyAndCompletedPaymentHeader() {
    let result = ReceiptParser.parse(lines: ["微信支付", "支付成功", "¥", "28.00", "收款方 松屋", "交易时间 2026年10月27日 12:05"])
    #expect(result.suggestedAmount?.amountMinor == 2800)
    #expect(result.merchant == "松屋")
    #expect(result.channel == .wechat)
}

@Test func receiptDoesNotTreatMetadataAndStatusBarNumbersAsMoney() {
    let result = ReceiptParser.parse(lines: ["9:41", "100%", "微信支付", "订单号 202610271234567890", "手机号 13800138000", "交易时间 2026-10-27 12:05:00"])
    #expect(result.amountCandidates.isEmpty)
    #expect(result.suggestedAmount == nil)
    #expect(result.merchant == nil)
}

@Test func receiptAmbiguousAmountsAndMissingDateRequireReview() {
    let result = ReceiptParser.parse(lines: ["¥20.00", "¥30.00", "商家 某某商店"])
    #expect(result.amountCandidates.count == 2)
    #expect(result.suggestedAmount == nil)
    #expect(result.occurredAt == nil)
    #expect(result.warnings.contains { $0.contains("金额尚不能确定") })
    #expect(result.warnings.contains { $0.contains("交易日期") })
}

@Test func receiptKeepsCurrenciesAndRejectsUnsupportedFractionalPrecision() {
    let yen = ReceiptParser.parse(lines: ["付款金额 JPY 1,500", "收款方 松屋"])
    #expect(yen.suggestedAmount?.amountMinor == 1500)
    #expect(yen.suggestedAmount?.currencyCode == "JPY")
    let hkd = ReceiptParser.parse(lines: ["实际支付 HK$28.50"])
    #expect(hkd.suggestedAmount?.amountMinor == 2850)
    #expect(hkd.suggestedAmount?.currencyCode == "HKD")
    let invalidYen = ReceiptParser.parse(lines: ["付款金额 JPY1,500.50"])
    #expect(invalidYen.amountCandidates.isEmpty)
    #expect(invalidYen.warnings.contains { $0.contains("小数位") })
    let invalidYuan = ReceiptParser.parse(lines: ["实际付款 CNY0.001"])
    #expect(invalidYuan.amountCandidates.isEmpty)
}

@Test func receiptActualYuanPaymentDoesNotInheritOriginalForeignCurrency() {
    let result = ReceiptParser.parse(lines: ["原币金额 JPY1,500", "人民币实际支付 ¥75.00"])
    #expect(result.suggestedAmount?.amountMinor == 7500)
    #expect(result.suggestedAmount?.currencyCode == "CNY")
    let suffix = ReceiptParser.parse(lines: ["原币金额 JPY1,500", "实际支付 75.00元"])
    #expect(suffix.suggestedAmount?.currencyCode == "CNY")
}

@Test func receiptRefundAndPendingStatusAreNotSilentlyRecordedAsCompletedExpense() {
    let refund = ReceiptParser.parse(lines: ["支付宝", "退款成功", "原实际付款 ¥100.00", "退款金额 ¥50.00"])
    #expect(refund.kind == .income)
    #expect(refund.suggestedAmount?.amountMinor == 5000)
    #expect(refund.warnings.contains { $0.contains("退款到账") })
    let pending = ReceiptParser.parse(lines: ["微信支付", "待付款", "实付金额 ¥42.50"])
    #expect(pending.suggestedAmount == nil)
    #expect(pending.amountCandidates.first?.amountMinor == 4250)
    #expect(pending.warnings.contains { $0.contains("不是已完成") })
}

@Test func receiptRejectsImpossibleDatesAndDoesNotInventUnlabeledClockDate() {
    let invalid = ReceiptParser.parse(lines: ["支付时间 2026-02-30 12:05", "付款金额 ¥10"])
    #expect(invalid.occurredAt == nil)
    let clock = ReceiptParser.parse(lines: ["今天 12:05", "付款金额 ¥10"], referenceDate: receiptDate(), calendar: receiptCalendar())
    #expect(clock.occurredAt == nil)
    let relative = ReceiptParser.parse(lines: ["支付时间 昨天 12:05", "付款金额 ¥10"], referenceDate: receiptDate(), calendar: receiptCalendar())
    #expect(relative.occurredAt == receiptDate(26))
    let split = ReceiptParser.parse(lines: ["支付时间", "2026-10-27", "12:05:00", "付款金额 ¥10"], calendar: receiptCalendar())
    #expect(split.occurredAt == receiptDate())
    #expect(split.hasExplicitTime)
}

@Test func receiptFingerprintIsDeterministicWithoutRequiringAnOfficialTransactionID() {
    let first = ReceiptParser.parse(lines: [" 支付宝 ", "实际付款 ￥12.50", "商家 某某书店"])
    let second = ReceiptParser.parse(lines: ["支付宝", "实际付款 ¥12.50", "商家 某某书店"])
    #expect(first.externalID == second.externalID)
    #expect(first.externalID.hasPrefix("receipt:sha256:"))
    #expect(first.categoryRaw == BuiltInCategory.study.rawValue)
}

@Test func receiptOfficialIDMatchesCSVAndSameImageMatchesRegardlessOfEditedFields() {
    let record = MoneyTransaction(amountMinor: 4250, channel: .wechat, externalID: "wechat:420026102700012345")
    let exact = ReceiptDuplicateMatcher.check(amountMinor: 4250, currencyCode: "CNY", kind: .expense,
        occurredAt: nil, merchant: "", externalID: "receipt:wechat:tx:420026102700012345", existing: [record])
    #expect(exact.exactIDs == [record.id])
    let image = MoneyTransaction(amountMinor: 1200, externalID: "receipt:sha256:abc123")
    let sameImage = ReceiptDuplicateMatcher.check(amountMinor: 1500, currencyCode: "JPY", kind: .income,
        occurredAt: nil, merchant: "", externalID: "receipt:sha256:abc123", existing: [image])
    #expect(sameImage.exactIDs == [image.id])
}

@Test func receiptSimilarityRequiresSameCurrencyMerchantDateAndNearbyKnownTime() {
    let record = MoneyTransaction(amountMinor: 4250, currencyCode: "CNY", occurredAt: receiptDate(), merchant: "M Stand")
    func check(currency: String = "CNY", merchant: String = "m stand", date: Date? = receiptDate(), timed: Bool = true) -> ReceiptDuplicateCheck {
        ReceiptDuplicateMatcher.check(amountMinor: 4250, currencyCode: currency, kind: .expense, occurredAt: date,
            merchant: merchant, externalID: nil, existing: [record], hasExplicitTime: timed, calendar: receiptCalendar())
    }
    #expect(check().possibleIDs == [record.id])
    #expect(check(currency: "JPY").possibleIDs.isEmpty)
    #expect(check(merchant: "").possibleIDs.isEmpty)
    #expect(check(date: nil).possibleIDs.isEmpty)
    #expect(check(date: receiptDate().addingTimeInterval(180)).possibleIDs.isEmpty)
    #expect(check(date: receiptDate(hour: 18), timed: false).possibleIDs == [record.id])
    #expect(check(date: receiptDate(28), timed: false).possibleIDs.isEmpty)
}

@Test func receiptRefundReusingOriginalOrderIDIsOnlyAPossibleDuplicate() {
    let original = MoneyTransaction(amountMinor: 10000, kind: .expense, externalID: "alipay:20261027220000123456")
    let refund = ReceiptDuplicateMatcher.check(amountMinor: 5000, currencyCode: "CNY", kind: .income,
        occurredAt: receiptDate(), merchant: "商家", externalID: "receipt:alipay:tx:20261027220000123456", existing: [original])
    #expect(refund.exactIDs.isEmpty)
    #expect(refund.possibleIDs == [original.id])
}

private func receiptCSVItem(
    source: StatementSource = .wechat,
    amountMinor: Int = 4250,
    currencyCode: String = "CNY",
    kind: TransactionKind = .expense
) -> ImportedTransaction {
    let identifier = source.rawValue + ":20261027000123456789"
    return ImportedTransaction(
        id: identifier, source: source, occurredAt: receiptDate(), kind: kind,
        amountMinor: amountMinor, currencyCode: currencyCode,
        categoryRaw: BuiltInCategory.dining.rawValue,
        channel: source == .wechat ? .wechat : .alipay, merchant: "松屋", note: "",
        externalID: identifier, isRefund: kind == .income, isTransfer: false
    )
}

@Test func receiptSavedBeforeCSVIsDeduplicatedForBothPaymentProviders() {
    for source in [StatementSource.wechat, .alipay] {
        let item = receiptCSVItem(source: source)
        let screenshot = MoneyTransaction(
            amountMinor: 4250, currencyCode: "CNY", kind: .expense,
            occurredAt: receiptDate(), merchant: "松屋",
            externalID: "receipt:\(source.rawValue):tx:20261027000123456789"
        )
        #expect(ReceiptDuplicateMatcher.isExactImportDuplicate(item, existing: [screenshot]))
        #expect(!ReceiptDuplicateMatcher.isExactImportDuplicate(item, existing: []))
    }
}

@Test func receiptBeforeCSVDoesNotSilentlyDiscardRefundDifferentAmountOrCurrency() {
    let screenshot = MoneyTransaction(
        amountMinor: 4250, currencyCode: "CNY", kind: .expense,
        occurredAt: receiptDate(), merchant: "松屋",
        externalID: "receipt:wechat:tx:20261027000123456789"
    )
    #expect(!ReceiptDuplicateMatcher.isExactImportDuplicate(receiptCSVItem(kind: .income), existing: [screenshot]))
    #expect(!ReceiptDuplicateMatcher.isExactImportDuplicate(receiptCSVItem(amountMinor: 2000), existing: [screenshot]))
    #expect(!ReceiptDuplicateMatcher.isExactImportDuplicate(receiptCSVItem(currencyCode: "JPY"), existing: [screenshot]))
}

@Test @MainActor func shortcutAutomaticallySavesActualAmountAndSkipsDuplicate() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = container.mainContext
    let parsed = ReceiptParser.parse(lines: ["微信支付", "支付成功", "实付金额 ¥28.50", "优惠 ¥6.50", "收款方 星河咖啡", "交易时间 2026-10-27 12:05:00", "交易单号 4200000000202610270000000285"])
    #expect(parsed.permitsAutomaticRecording)
    guard case .saved(let id) = try ReceiptAutomaticRecorder.record(parsed, in: context) else {
        Issue.record("Expected automatic save")
        return
    }
    #expect(try ReceiptAutomaticRecorder.record(parsed, in: context) == .duplicate(id))
    let rows = try context.fetch(FetchDescriptor<MoneyTransaction>())
    #expect(rows.count == 1)
    #expect(rows.first?.amountMinor == 2850)
    #expect(rows.first?.channel == .wechat)
    #expect(rows.first?.categoryRaw == BuiltInCategory.dining.rawValue)
}

@Test @MainActor func shortcutUncertainOrIncompleteImagesNeverWriteRecords() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = container.mainContext
    let cases: [[String]] = [
        ["微信支付", "支付成功", "¥20", "¥30"],
        ["支付宝", "待付款", "实付 ¥20"],
        ["支付宝", "实付 ¥20"],
        ["微信支付", "支付宝", "支付成功", "实付 ¥20"],
        ["10:10", "iPhone镜像", "已连接", "91%"],
        ["支付宝", "支付成功", "实际付款 $20"]
    ]
    for lines in cases {
        let parsed = ReceiptParser.parse(lines: lines)
        #expect(!parsed.permitsAutomaticRecording)
        guard case .needsReview = try ReceiptAutomaticRecorder.record(parsed, in: context) else {
            Issue.record("Uncertain input must not be saved")
            continue
        }
    }
    #expect(try context.fetchCount(FetchDescriptor<MoneyTransaction>()) == 0)
}

@Test @MainActor func shortcutUsesCaptureTimeAndRecordsSimilarPaymentsWithoutConfirmation() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = container.mainContext
    let parsed = ReceiptParser.parse(lines: ["支付宝", "付款成功", "¥12.50", "收款方 小店"])
    guard case .saved = try ReceiptAutomaticRecorder.record(parsed, in: context, capturedAt: receiptDate()) else {
        Issue.record("Expected payment-success page to save with capture time")
        return
    }
    let rows = try context.fetch(FetchDescriptor<MoneyTransaction>())
    #expect(rows.first?.occurredAt == receiptDate())
    #expect(rows.first?.note.contains("按截图时刻") == true)
    let changed = ReceiptParser.parse(lines: ["支付宝", "付款成功", "¥12.50", "收款方 小店", "10:11"])
    guard case .saved = try ReceiptAutomaticRecorder.record(changed, in: context, capturedAt: receiptDate()) else {
        Issue.record("Similar transaction must be saved without confirmation")
        return
    }
    #expect(try context.fetchCount(FetchDescriptor<MoneyTransaction>()) == 2)
}

@Test @MainActor func shortcutCompletedRefundIsIncome() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let parsed = ReceiptParser.parse(lines: ["支付宝", "退款成功", "原实际付款 ¥100", "退款金额 ¥50", "商家 小店"])
    guard case .saved = try ReceiptAutomaticRecorder.record(parsed, in: container.mainContext) else {
        Issue.record("Expected completed refund")
        return
    }
    let rows = try container.mainContext.fetch(FetchDescriptor<MoneyTransaction>())
    #expect(rows.first?.amountMinor == 5000)
    #expect(rows.first?.kind == .income)
}


@Test @MainActor func shortcutRecordsSimilarPaymentsWithoutMerchant() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = container.mainContext
    let first = ReceiptParser.parse(lines: ["支付宝", "付款成功", "¥12.50", "10:10"])
    guard case .saved = try ReceiptAutomaticRecorder.record(first, in: context, capturedAt: receiptDate()) else {
        Issue.record("Expected first capture to save")
        return
    }
    let next = ReceiptParser.parse(lines: ["支付宝", "付款成功", "¥12.50", "10:11"])
    guard case .saved = try ReceiptAutomaticRecorder.record(next, in: context, capturedAt: receiptDate().addingTimeInterval(30)) else {
        Issue.record("Similar payment without a merchant must still be saved")
        return
    }
    #expect(try context.fetchCount(FetchDescriptor<MoneyTransaction>()) == 2)
}

@Test @MainActor func shortcutMinimalCompletedTransferWithRecipientBetweenStatusAndAmount() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = container.mainContext
    let parsed = ReceiptParser.parse(lines: ["11:06", "5G", "100", "支付成功", "待测试收款人确认收款", "¥ 0.01", "完成"])
    #expect(parsed.suggestedAmount?.amountMinor == 1)
    #expect(parsed.permitsAutomaticRecording)
    #expect(parsed.merchant == "测试收款人")
    guard case .saved = try ReceiptAutomaticRecorder.record(parsed, in: context) else {
        Issue.record("Minimal completed payment must automatically save one cent")
        return
    }
    let records = try context.fetch(FetchDescriptor<MoneyTransaction>())
    #expect(records.count == 1)
    #expect(records.first?.amountMinor == 1)
    #expect(records.first?.channel == .other)
    #expect(records.first?.kind == .expense)
}

@Test func minimalCompletedPaymentStillRejectsMultipleAmountsAndIncompleteStates() {
    let ambiguous = ReceiptParser.parse(lines: ["支付成功", "待测试收款人确认收款", "¥0.01", "¥9.99", "完成"])
    #expect(!ambiguous.permitsAutomaticRecording)
    let failed = ReceiptParser.parse(lines: ["支付失败", "待测试收款人确认收款", "¥0.01", "完成"])
    #expect(!failed.permitsAutomaticRecording)
    let pending = ReceiptParser.parse(lines: ["等待付款", "¥0.01", "完成"])
    #expect(!pending.permitsAutomaticRecording)
}

@Test @MainActor func shortcutMinimalTransferWithOCRDamagedYuanSymbol() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = container.mainContext
    let parsed = ReceiptParser.parse(lines: ["09:41 !!! 5G 100", "支付成功", "待测试收款人确认收款", "· 0.01", "完成"])
    #expect(parsed.suggestedAmount?.amountMinor == 1)
    #expect(parsed.permitsAutomaticRecording)
    guard case .saved = try ReceiptAutomaticRecorder.record(parsed, in: context) else {
        Issue.record("Actual OCR text must save one cent")
        return
    }
    #expect(try context.fetch(FetchDescriptor<MoneyTransaction>()).first?.amountMinor == 1)
    for lines in [["支付成功", "· 0.01"], ["支付失败", "待测试收款人确认收款", "· 0.01"], ["支付成功", "待测试收款人确认收款", "· 0.01", "· 9.99"]] {
        #expect(!ReceiptParser.parse(lines: lines).permitsAutomaticRecording)
    }
}

@Test @MainActor func shortcutTransferWithOverlayOnSuccessTextAndDamagedCurrency() throws {
    let container = try LifeOSModelContainer.make(inMemory: true)
    let context = container.mainContext
    let ocr = ["09:41 !! 5G 100", "待测试收款人确认收款", "·0.01", "完成"]
    let parsed = ReceiptParser.parse(lines: ocr)
    #expect(parsed.permitsAutomaticRecording)
    #expect(parsed.suggestedAmount?.amountMinor == 1)
    #expect(parsed.merchant == "测试收款人")
    guard case .saved = try ReceiptAutomaticRecorder.record(parsed, in: context) else {
        Issue.record("Expected the initiated transfer to be recorded")
        return
    }
    let row = try context.fetch(FetchDescriptor<MoneyTransaction>()).first
    #expect(row?.amountMinor == 1)
    #expect(row?.note.contains("收款方待确认") == true)
}

@Test func shortcutOverlayTransferRejectsIncompleteAndAmbiguousInputs() {
    let invalid: [[String]] = [
        ["待测试收款人确认收款", "·0.01"],
        ["支付失败", "待测试收款人确认收款", "·0.01", "完成"],
        ["等待付款", "待测试收款人确认收款", "·0.01", "完成"],
        ["待测试收款人确认收款", "·0.01", "·1.00", "完成"],
        ["待测试收款人确认收款", "·0.01", "¥2.00", "完成"],
        ["待测试收款人确认收款", "·0.01", "完成", "退款中"],
        ["待测试收款人确认收款", "·0.001", "完成"]
    ]
    for lines in invalid { #expect(!ReceiptParser.parse(lines: lines).permitsAutomaticRecording) }
}

@Test @MainActor func shortcutWechatBillNegativeAmountBeforeSuccessStatus() throws {
    let lines = ["15:36 89+1", "× 全部账单", "测试电商商家", "-19.90", "当前状态 支付成功", "支付时间 2026年10月27日 17:57:17", "收单机构 财付通支付科技有限公司", "支付方式 零钱", "交易单号 12345678901234567890"]
    let parsed = ReceiptParser.parse(lines: lines)
    #expect(parsed.suggestedAmount?.amountMinor == 1990)
    #expect(parsed.suggestedAmount?.currencyCode == "CNY")
    #expect(parsed.merchant == "测试电商商家")
    #expect(parsed.permitsAutomaticRecording)
    let container = try LifeOSModelContainer.make(inMemory: true)
    guard case .saved = try ReceiptAutomaticRecorder.record(parsed, in: container.mainContext) else { Issue.record("Expected successful bill to save"); return }
    let record = try container.mainContext.fetch(FetchDescriptor<MoneyTransaction>()).first
    #expect(record?.amountMinor == 1990)
    #expect(record?.kind == .expense)
}

@Test func shortcutBillNegativeAmountRequiresUnambiguousPaidStatus() {
    for lines in [
        ["测试商家", "-19.90", "当前状态 支付失败", "收单机构 财付通支付科技有限公司"],
        ["测试商家", "-19.90", "当前状态 待付款", "收单机构 财付通支付科技有限公司"],
        ["测试商家", "-19.90", "当前状态 支付成功"],
        ["测试商家", "-19.90", "-20.00", "当前状态 支付成功", "收单机构 财付通支付科技有限公司"],
        ["测试商家", "-19.901", "当前状态 支付成功", "收单机构 财付通支付科技有限公司"]
    ] { #expect(!ReceiptParser.parse(lines: lines).permitsAutomaticRecording) }
}

@Test @MainActor func shortcutAlipayAutomaticDeductionBillActualOCR() throws {
    let lines = ["16:16 969", "轻点背面", "检测到轻点三下 全部账单", "示例数字服务 >", "-9.90", "自动扣款成功", "管理自动续费 示例服务", "支付时间 2026-10-28 10:20:00", "付款方式 账户余额"]
    let parsed = ReceiptParser.parse(lines: lines, calendar: receiptCalendar())
    #expect(parsed.suggestedAmount?.amountMinor == 990)
    #expect(parsed.suggestedAmount?.currencyCode == "CNY")
    #expect(parsed.permitsAutomaticRecording)
    #expect(parsed.merchant == "示例数字服务")
    #expect(receiptCalendar().isDate(parsed.occurredAt ?? .distantPast, inSameDayAs: receiptDate(28)))
    let container = try LifeOSModelContainer.make(inMemory: true)
    guard case .saved = try ReceiptAutomaticRecorder.record(parsed, in: container.mainContext) else { Issue.record("Expected completed automatic deduction to be saved"); return }
    let record = try container.mainContext.fetch(FetchDescriptor<MoneyTransaction>()).first
    #expect(record?.amountMinor == 990)
    #expect(record?.kind == .expense)
    #expect(receiptCalendar().isDate(record?.occurredAt ?? .distantPast, inSameDayAs: receiptDate(28)))
}

@Test func automaticDeductionRejectsFailedIncompleteAmbiguousOrForeignCases() {
    let base = ["示例服务", "-9.90", "自动扣款成功", "管理自动续费", "支付时间 2026-10-28 10:20:00"]
    let invalid = [
        ["示例服务", "-9.90", "自动扣款失败", "管理自动续费", "支付时间 2026-10-28 10:20:00"],
        ["示例服务", "-9.90", "自动扣款中", "管理自动续费", "支付时间 2026-10-28 10:20:00"],
        base + ["退款中"], base + ["¥19.90"], base + ["-19.90"],
        ["示例服务", "-9.901", "自动扣款成功", "管理自动续费", "支付时间 2026-10-28 10:20:00"],
        base + ["USD"], ["示例服务", "-9.90", "自动扣款成功"]
    ]
    for lines in invalid { #expect(!ReceiptParser.parse(lines: lines).permitsAutomaticRecording) }
}

// Synthetic representative OCR inputs. They test shared format patterns, not live app UI.
@Test @MainActor func commonPaymentReceiptFormatsAutomaticallySave() throws {
    let formats: [([String], Int, String)] = [
        (["支付宝", "交易成功", "实付款 12.50", "付款时间 2026-10-27 12:05:00"], 1250, "CNY"),
        (["支付宝", "付款成功", "-9.90", "交易时间 2026-10-27 12:05:00"], 990, "CNY"),
        (["支付宝", "-7.80", "交易状态", "成功", "交易时间 2026-10-27 12:05:00"], 780, "CNY"),
        (["云闪付", "-10.50", "交易成功", "交易时间 2026-10-27 12:05:00"], 1050, "CNY"),
        (["银行卡", "付款成功", "消费金额 66.80", "交易时间 2026-10-27 12:05:00"], 6680, "CNY"),
        (["Apple Pay", "Payment Successful", "USD 10.00", "交易时间 2026-10-27 12:05:00"], 1000, "USD"),
        (["Apple Pay", "Payment Successful", "JPY 100", "交易时间 2026-10-27 12:05:00"], 100, "JPY"),
        (["美团", "已支付", "实付金额 23.50", "付款时间 2026-10-27 12:05:00"], 2350, "CNY"),
        (["京东", "付款成功", "付款金额 41.20", "付款时间 2026-10-27 12:05:00"], 4120, "CNY"),
        (["淘宝", "交易成功", "实付款 15.00", "付款时间 2026-10-27 12:05:00"], 1500, "CNY"),
        (["抖音", "已付款", "已付金额 35.00", "付款时间 2026-10-27 12:05:00"], 3500, "CNY")
    ]
    for (lines, amount, currency) in formats {
        let container = try LifeOSModelContainer.make(inMemory: true)
        let parsed = ReceiptParser.parse(lines: lines, calendar: receiptCalendar())
        #expect(parsed.permitsAutomaticRecording, "Expected completed format: \(lines)")
        #expect(parsed.suggestedAmount?.amountMinor == amount)
        #expect(parsed.suggestedAmount?.currencyCode == currency)
        #expect(parsed.occurredAt == receiptDate())
        guard case .saved = try ReceiptAutomaticRecorder.record(parsed, in: container.mainContext) else {
            Issue.record("Expected representative payment to save: \(lines)"); continue
        }
        let row = try container.mainContext.fetch(FetchDescriptor<MoneyTransaction>()).first
        #expect(row?.amountMinor == amount)
        #expect(row?.kind == .expense)
    }
}

@Test func commonPaymentScreensRejectAmbiguityAndNonPayments() {
    let invalid: [[String]] = [
        ["云闪付", "-10.50", "交易失败"],
        ["云闪付", "-10.50", "交易成功", "已撤销"],
        ["支付宝", "付款成功", "-9.90", "-8.80"],
        ["支付宝", "付款成功", "-9.90", "¥8.80"],
        ["淘宝", "待付款", "实付款 15.00"],
        ["淘宝", "未支付成功", "实付款 15.00"],
        ["淘宝", "未交易成功", "实付款 15.00"],
        ["京东", "支付成功", "退款中", "实付金额 15.00"],
        ["美团", "未支付", "已支付优惠券", "实付金额 23.50"],
        ["京东", "订单已完成", "应付金额 41.20"],
        ["Apple Pay", "Payment Successful", "-10.00"],
        ["Apple Pay", "Payment Successful", "¥100"],
        ["Apple Pay", "Payment Successful", "USD 10.00", "Payment Failed"],
        ["支付宝", "-7.80", "订单状态", "成功"],
        ["支付宝", "交易失败", "已支付 12.50"],
        ["银行卡", "转账成功", "账户余额 ¥999.00"],
        ["云闪付", "支付成功", "-0.001"]
    ]
    for lines in invalid { #expect(!ReceiptParser.parse(lines: lines).permitsAutomaticRecording, "Should reject \(lines)") }
}

@Test func receiptNeverUsesPaymentStatusOrProviderAsMerchant() {
    let statusBefore = ReceiptParser.parse(lines: ["支付宝", "付款成功", "-9.90"])
    let providerBefore = ReceiptParser.parse(lines: ["云闪付", "-10.50", "交易成功"])
    #expect(statusBefore.merchant == nil)
    #expect(providerBefore.merchant == nil)
}

@Test @MainActor func shortcutAlipaySuccessYuanGlyphMisreadAsDot() throws {
    let lines = ["16:32 5G 96%", "完成", "支", "支付成功", "·0.01", "付款方式 账户余额", "收款方 测试商家 >"]
    let parsed = ReceiptParser.parse(lines: lines, calendar: receiptCalendar())
    #expect(parsed.permitsAutomaticRecording)
    #expect(parsed.suggestedAmount?.amountMinor == 1)
    #expect(parsed.suggestedAmount?.currencyCode == "CNY")
    let container = try LifeOSModelContainer.make(inMemory: true)
    let capturedAt = receiptDate(28)
    guard case .saved = try ReceiptAutomaticRecorder.record(parsed, in: container.mainContext, capturedAt: capturedAt) else {
        Issue.record("Expected payment-success screenshot to be saved")
        return
    }
    let row = try container.mainContext.fetch(FetchDescriptor<MoneyTransaction>()).first
    #expect(row?.amountMinor == 1)
    #expect(row?.kind == .expense)
    #expect(row?.occurredAt == capturedAt)
}

@Test func damagedYuanOnPaymentSuccessRejectsAmbiguousAndUnpaid() {
    let valid = ["完成", "支", "支付成功", "·0.01", "付款方式 账户余额", "收款方 测试商家"]
    let invalid = [
        ["完成", "支付失败", "·0.01", "付款方式 账户余额", "收款方 测试商家"],
        ["完成", "待付款", "·0.01", "付款方式 账户余额", "收款方 测试商家"],
        valid + ["退款中"], valid + ["·2.00"], valid + ["¥2.00"], valid + ["JPY"], valid + ["USD"],
        ["完成", "支付成功", "·0.01", "收款方 测试商家"],
        ["完成", "支付成功", "·0.01", "付款方式 账户余额"],
        ["完成", "支付成功", "·0.01"],
        ["完成", "支付成功", "·0.001", "付款方式 账户余额", "收款方 测试商家"]
    ]
    for lines in invalid { #expect(!ReceiptParser.parse(lines: lines).permitsAutomaticRecording, "Should reject \(lines)") }
}

@Test func wechatMerchantSuccessWithPromotionKeepsTwoYuanAmount() {
    let result = ReceiptParser.parse(lines: ["09:41", "5G", "35", "支付成功", "示例餐饮管理有限公司", "¥2.00", "摇一摇，有优惠", "完成"])
    #expect(result.suggestedAmount?.amountMinor == 200)
    #expect(result.merchant == "示例餐饮管理有限公司")
    #expect(result.permitsAutomaticRecording)
}

@Test func wechatCompanySuccessActualDotOCR() {
    let result = ReceiptParser.parse(lines: ["09:41 :! 5G 6⑤", "支付成功", "示例餐饮管理有限公司", "·2.00", "摇一摇，有优惠", "完成"])
    #expect(result.suggestedAmount?.amountMinor == 200)
    #expect(result.merchant == "示例餐饮管理有限公司")
    #expect(result.permitsAutomaticRecording)
}

@Test func compactCompanyDotAmountDoesNotAdmitUnpaidOrPromotions() {
    for lines in [
        ["待支付", "示例餐饮管理有限公司", "·2.00", "完成"],
        ["支付成功", "摇一摇，有优惠", "·2.00", "完成"],
        ["支付成功", "示例餐饮管理有限公司", "·2.00", "支付失败", "完成"],
        ["支付成功", "示例餐饮管理有限公司", "·2.00", "·3.00", "完成"]
    ] {
        #expect(!ReceiptParser.parse(lines: lines).permitsAutomaticRecording)
    }
}
