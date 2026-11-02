#if DEBUG
import Foundation

/// 仅用于 DEBUG 截图 / 预览的示例账单，不会进入 Release。
enum DebugSamples {
    static let wechatStatement = """
    微信支付账单明细
    微信昵称：[LifeOS 测试], 起始时间：[2026-10-01 00:00:00] 终止时间：[2026-10-31 23:59:59]
    导出类型：[全部]
    ----------------------
    交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
    2026-10-23 12:05:00,商户消费,松屋,午餐,支出,¥42.50,零钱,支付成功,DEMO001,M001,
    2026-10-22 16:20:00,商户消费,滴滴出行,打车,支出,36.00,零钱,支付成功,DEMO002,M002,
    2026-10-21 10:00:00,转账,张三,转账,支出,100.00,零钱,对方已收钱,DEMO003,M003,
    2026-10-20 09:00:00,商户消费,京东,退款,不计收支,58.00,零钱,已全额退款,DEMO004,M004,
    """

    static func parseSample() -> StatementParseResult? {
        guard let data = wechatStatement.data(using: .utf8) else { return nil }
        return try? StatementImporter.parse(data: data, fileName: "微信支付账单_示例.csv")
    }
}
#endif
