#if DEBUG
import UIKit

/// 仅 QA scheme 生成的文字样张；走真实 Vision 流程，不预置识别结果。
@MainActor
enum ReceiptDebugSample {
    static func imageData() -> Data? {
        let lines = [
            "测试样张 · 不是真实交易", "微信支付", "支付成功", "星河咖啡",
            "实付金额 ￥28.50", "原价 ￥35.00", "优惠 ￥6.50", "收款方 星河咖啡",
            "交易时间 2026-10-27 12:05:00", "支付方式 微信支付",
            "交易单号 4200000000202610270000000285"
        ]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1290, height: 2100), format: format)
        return renderer.pngData { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 1290, height: 2100))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.black
            ]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 70, y: 80 + index * 160), withAttributes: attributes)
            }
        }
    }
}
#endif
