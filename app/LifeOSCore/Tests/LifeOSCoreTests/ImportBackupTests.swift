import Foundation
import Testing
@testable import LifeOSCore

private let wechatSample = """
微信支付账单明细
微信昵称：[测试], 起始时间：[2026-10-01 00:00:00] 终止时间：[2026-10-31 23:59:59]
导出类型：[全部]
----------------------
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-10-23 12:05:00,商户消费,松屋,午餐,支出,¥42.50,零钱,支付成功,TX001,M001,
2026-10-22 16:20:00,商户消费,滴滴出行,打车,支出,36.00,零钱,支付成功,TX002,M002,
2026-10-21 10:00:00,转账,张三,转账,支出,100.00,零钱,对方已收钱,TX003,M003,
2026-10-20 09:00:00,商户消费,京东,退款,不计收支,58.00,零钱,已全额退款,TX004,M004,
2026-10-19 08:00:00,商户消费,便利店,"咖啡, 拿铁",支出,28.00,零钱,支付成功,TX005,M005,
2026-10-18 08:00:00,商户消费,便利店,"咖啡, 拿铁",支出,28.00,零钱,支付成功,TX005,M005,
"""

private let alipaySample = """
支付宝交易记录明细查询
账号:[test@example.com]
起始时间:[2026-10-01] 终止时间:[2026-10-31]
----------------------------------------------------
交易号,商家订单号,交易创建时间,付款时间,最近修改时间,交易来源地,类型,交易对方,商品名称,金额（元）,收/支,交易状态,服务费（元）,成功退款（元）,备注,资金状态
2026102312000001,M001,2026-10-23 12:00:00,2026-10-23 12:01:00,2026-10-23 12:01:00,支付宝,即时到账交易,某某超市,"日用品, 清洁",128.50,支出,交易成功,0.00,0.00,,已支出
2026102212000002,M002,2026-10-22 09:00:00,2026-10-22 09:01:00,2026-10-22 09:01:00,支付宝,即时到账交易,某某公司,工资,8000.00,收入,交易成功,0.00,0.00,,已收入
"""

@Test func parsesWeChatStatementWithRefundTransferAndDedupe() throws {
    let data = try #require(wechatSample.data(using: .utf8))
    let result = try StatementImporter.parse(data: data, fileName: "微信支付账单.csv")

    #expect(result.source == .wechat)
    #expect(result.transactions.count == 5)
    #expect(result.warnings.contains { $0.contains("重复") })

    let lunch = try #require(result.transactions.first { $0.merchant == "松屋" })
    #expect(lunch.kind == .expense)
    #expect(lunch.amountMinor == 4250)
    #expect(lunch.categoryRaw == BuiltInCategory.dining.rawValue)
    #expect(lunch.channel == .wechat)

    let transfer = try #require(result.transactions.first { $0.isTransfer })
    #expect(transfer.categoryRaw == "转账")
    #expect(transfer.kind == .expense)

    let refund = try #require(result.transactions.first { $0.isRefund })
    #expect(refund.kind == .income)
    #expect(refund.categoryRaw == "退款")
    #expect(refund.amountMinor == 5800)

    let coffee = try #require(result.transactions.first { $0.note.contains("拿铁") })
    #expect(coffee.merchant == "便利店")
    #expect(coffee.categoryRaw == BuiltInCategory.dining.rawValue)
}

@Test func parsesAlipayStatement() throws {
    let data = try #require(alipaySample.data(using: .utf8))
    let result = try StatementImporter.parse(data: data, fileName: "支付宝账单.csv")

    #expect(result.source == .alipay)
    #expect(result.transactions.count == 2)

    let shopping = try #require(result.transactions.first { $0.merchant == "某某超市" })
    #expect(shopping.kind == .expense)
    #expect(shopping.amountMinor == 12_850)
    #expect(shopping.channel == .alipay)
    #expect(shopping.note.contains("清洁"))

    let income = try #require(result.transactions.first { $0.kind == .income })
    #expect(income.amountMinor == 800_000)
}

@Test func rejectsUnknownStatementFormat() throws {
    let data = try #require("姓名,年龄\n张三,20\n".data(using: .utf8))
    #expect(throws: StatementImportError.self) {
        _ = try StatementImporter.parse(data: data)
    }
}

@Test func backupArchiveRoundTrips() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let transaction = MoneyTransaction(amountMinor: 1234, currencyCode: "CNY", kind: .income, categoryRaw: "红包", channel: .wechat, occurredAt: now, note: "测试", merchant: "朋友", externalID: "wechat:TX1")
    let budget = Budget(monthKey: "2026-10", amountMinor: 300_000, currencyCode: "CNY")
    let schedule = ScheduleTask(title: "训练", startAt: now, durationMinutes: 60, priority: .high, reminderMinutesBefore: 10)

    let archive = BackupArchive(
        exportedAt: now,
        transactions: [BackupTransaction(transaction)],
        budgets: [BackupBudget(budget)],
        scheduleTasks: [BackupScheduleTask(schedule)],
        customCategories: [BackupCustomCategory(name: "宠物", symbol: "pawprint.fill", colorHex: 0x9C752F)]
    )

    let data = try archive.encoded()
    let decoded = try BackupArchive.decoded(from: data)

    #expect(decoded.transactions.count == 1)
    #expect(decoded.transactions[0].amountMinor == 1234)
    #expect(decoded.transactions[0].kindRaw == "income")
    #expect(decoded.transactions[0].externalID == "wechat:TX1")
    #expect(decoded.budgets[0].monthKey == "2026-10")
    #expect(decoded.scheduleTasks[0].priorityRaw == TaskPriority.high.rawValue)
    #expect(decoded.customCategories[0].name == "宠物")

    let restored = decoded.transactions[0].makeModel()
    #expect(restored.kind == .income)
    #expect(restored.categoryRaw == "红包")
}

@Test func backupArchiveRejectsUnknownSchemaVersion() throws {
    let archive = BackupArchive(schemaVersion: 99)
    let data = try archive.encoded()
    #expect(throws: BackupError.self) {
        _ = try BackupArchive.decoded(from: data)
    }
}
