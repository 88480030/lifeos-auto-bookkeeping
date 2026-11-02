import Testing
@testable import LifeOSCore

@Test func dailySpendingTierRespectsEveryBoundary() {
    #expect(DailySpendingTier.matching(expenseMinor: 0, currencyCode: "CNY") == nil)
    #expect(DailySpendingTier.matching(expenseMinor: -1, currencyCode: "CNY") == nil)
    for (index, tier) in DailySpendingTier.allCases.enumerated() {
        #expect(DailySpendingTier.matching(expenseMinor: tier.rawValue, currencyCode: "CNY") == tier)
        if index > 0 {
            let previous = DailySpendingTier.allCases[index - 1]
            #expect(DailySpendingTier.matching(expenseMinor: previous.rawValue + 1, currencyCode: "CNY") == tier)
        }
    }
    #expect(DailySpendingTier.matching(expenseMinor: 10_001, currencyCode: "CNY") == .hundred)
    #expect(!DailySpendingTier.isAboveHighestTier(expenseMinor: 10_000, currencyCode: "CNY"))
    #expect(DailySpendingTier.isAboveHighestTier(expenseMinor: 10_001, currencyCode: "CNY"))
}

@Test func dailySpendingTierNeverTreatsForeignCurrencyAsYuan() {
    #expect(DailySpendingTier.matching(expenseMinor: 2_000, currencyCode: "JPY") == nil)
    #expect(DailySpendingTier.matching(expenseMinor: 2_000, currencyCode: "USD") == nil)
    #expect(DailySpendingTier.matching(expenseMinor: 2_000, currencyCode: "cny") == .twenty)
    #expect(!DailySpendingTier.isAboveHighestTier(expenseMinor: 100_000, currencyCode: "JPY"))
}
