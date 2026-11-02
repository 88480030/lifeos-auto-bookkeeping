import Foundation

// MARK: - MoneyAmount

/// 金额以「最小货币单位」的整数保存，避免浮点误差。
/// 人民币 1 元 = 100 分；日元没有小数位，1 日元 = 1 个最小单位。
public struct MoneyAmount: Hashable, Codable, Sendable {
    public var minorUnits: Int
    public var currencyCode: String

    public init(minorUnits: Int, currencyCode: String) {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode.uppercased()
    }

    /// 该币种最小单位的小数位数。
    public var minorUnitDigits: Int {
        CurrencyCatalog.minorUnitDigits(for: currencyCode)
    }

    /// 转换成 Decimal，用于展示或单一币种内的计算。
    public var decimalValue: Decimal {
        var value = Decimal(minorUnits)
        for _ in 0..<minorUnitDigits {
            value /= 10
        }
        return value
    }
}

// MARK: - CurrencyCatalog

public enum CurrencyCatalog {
    public static let supportedCurrencyCodes: [String] = [
        "CNY", "JPY", "USD", "EUR", "HKD", "GBP", "KRW", "SGD", "AUD", "CAD"
    ]

    /// 不同币种的最小单位不同：日元 0 位，人民币 2 位，部分中东货币 3 位。
    public static func minorUnitDigits(for currencyCode: String) -> Int {
        switch currencyCode.uppercased() {
        case "JPY", "KRW", "VND", "CLP", "ISK":
            0
        case "BHD", "KWD", "OMR", "TND", "IQD", "JOD", "LYD":
            3
        default:
            2
        }
    }

    public static func symbol(for currencyCode: String) -> String {
        switch currencyCode.uppercased() {
        case "CNY": "¥"
        case "JPY": "JP¥"
        case "USD": "$"
        case "EUR": "€"
        case "HKD": "HK$"
        case "GBP": "£"
        case "KRW": "₩"
        case "SGD": "S$"
        case "AUD": "A$"
        case "CAD": "C$"
        default: currencyCode.uppercased()
        }
    }

    public static func displayName(for currencyCode: String) -> String {
        switch currencyCode.uppercased() {
        case "CNY": "人民币"
        case "JPY": "日元"
        case "USD": "美元"
        case "EUR": "欧元"
        case "HKD": "港币"
        case "GBP": "英镑"
        case "KRW": "韩元"
        case "SGD": "新加坡元"
        case "AUD": "澳元"
        case "CAD": "加元"
        default: currencyCode.uppercased()
        }
    }
}

// MARK: - MoneyMath

public enum MoneyMath {
    /// 单一币种的小计。汇总结果永远不会把不同币种直接相加。
    public struct CurrencyTotal: Hashable, Sendable, Identifiable {
        public var currencyCode: String
        public var minorUnits: Int

        public var id: String { currencyCode }

        public init(currencyCode: String, minorUnits: Int) {
            self.currencyCode = currencyCode.uppercased()
            self.minorUnits = minorUnits
        }

        public var money: MoneyAmount {
            MoneyAmount(minorUnits: minorUnits, currencyCode: currencyCode)
        }
    }

    /// 按币种分组求和，返回结果按币种代码排序，保证展示顺序稳定。
    public static func totalsByCurrency(_ amounts: [MoneyAmount]) -> [CurrencyTotal] {
        var totals: [String: Int] = [:]
        for amount in amounts {
            totals[amount.currencyCode, default: 0] += amount.minorUnits
        }
        return totals
            .map { CurrencyTotal(currencyCode: $0.key, minorUnits: $0.value) }
            .sorted { $0.currencyCode < $1.currencyCode }
    }
}

// MARK: - MoneyFormatter

public enum MoneyFormatter {
    /// 例如：12345 CNY -> "¥123.45"；1500 JPY -> "JP¥1,500"；-1234 CNY -> "-¥12.34"。
    public static func string(
        minorUnits: Int,
        currencyCode: String,
        showSymbol: Bool = true
    ) -> String {
        let digits = CurrencyCatalog.minorUnitDigits(for: currencyCode)
        let absolute = abs(minorUnits)
        let divisor = powerOfTen(digits)
        let whole = absolute / divisor
        let fraction = absolute % divisor

        var body = groupDigits(whole)
        if digits > 0 {
            body += "." + String(format: "%0\(digits)d", fraction)
        }
        if showSymbol {
            body = CurrencyCatalog.symbol(for: currencyCode) + body
        }
        return minorUnits < 0 ? "-" + body : body
    }

    private static func powerOfTen(_ exponent: Int) -> Int {
        var value = 1
        for _ in 0..<exponent {
            value *= 10
        }
        return value
    }

    private static func groupDigits(_ value: Int) -> String {
        let digits = String(value)
        var result = ""
        for (index, character) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 {
                result.append(",")
            }
            result.append(character)
        }
        return String(result.reversed())
    }
}
