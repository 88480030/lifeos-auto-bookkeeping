import Foundation

/// 人民币每日实际支出的五档。阈值均为分，非人民币不作换算或套档。
public enum DailySpendingTier: Int, CaseIterable, Identifiable, Sendable {
    case twenty = 2_000
    case thirty = 3_000
    case forty = 4_000
    case fifty = 5_000
    case hundred = 10_000

    public var id: Int { rawValue }
    public var upperBoundYuan: Int { rawValue / 100 }

    /// 超过 100 元仍使用第五档；调用方必须同时显示超出提示，不隐去真实金额。
    public static func matching(expenseMinor: Int, currencyCode: String) -> Self? {
        guard currencyCode.uppercased() == "CNY", expenseMinor > 0 else { return nil }
        return allCases.first { expenseMinor <= $0.rawValue } ?? .hundred
    }

    public static func isAboveHighestTier(expenseMinor: Int, currencyCode: String) -> Bool {
        currencyCode.uppercased() == "CNY" && expenseMinor > Self.hundred.rawValue
    }
}
