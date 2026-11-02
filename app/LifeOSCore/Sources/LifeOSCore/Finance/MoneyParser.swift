import Foundation

/// 把用户输入的金额字符串解析成最小货币单位整数。
/// 支持 "12.34"、"-12.34"、"1 234.56"；不使用浮点数，避免精度问题。
public enum MoneyParser {
    public static func minorUnits(from input: String, currencyCode: String) -> Int? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 去掉分组用的空格、逗号、中文逗号；小数点只保留最后一个分隔符。
        text = text.replacingOccurrences(of: " ", with: "")
        text = text.replacingOccurrences(of: ",", with: ".")
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        if parts.count == 2 {
            text = "\(parts[0]).\(parts[1])"
        }

        guard let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }

        let digits = CurrencyCatalog.minorUnitDigits(for: currencyCode)
        var scale = Decimal(1)
        for _ in 0..<digits {
            scale *= 10
        }

        var scaled = decimal * scale
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard rounded == scaled else {
            return nil // 小数位超过币种精度
        }

        let number = NSDecimalNumber(decimal: rounded)
        guard number != NSDecimalNumber.notANumber else { return nil }
        let intValue = number.intValue
        guard Decimal(intValue) == rounded else { return nil }

        return intValue
    }
}
