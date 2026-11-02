import Foundation
import Testing
@testable import LifeOSCore

@Test func minorUnitDigitsFollowCurrencyRules() {
    #expect(CurrencyCatalog.minorUnitDigits(for: "CNY") == 2)
    #expect(CurrencyCatalog.minorUnitDigits(for: "cny") == 2)
    #expect(CurrencyCatalog.minorUnitDigits(for: "JPY") == 0)
    #expect(CurrencyCatalog.minorUnitDigits(for: "BHD") == 3)
}

@Test func decimalValueUsesCurrencyScale() {
    #expect(MoneyAmount(minorUnits: 12345, currencyCode: "CNY").decimalValue == Decimal(12345) / Decimal(100))
    #expect(MoneyAmount(minorUnits: 1500, currencyCode: "JPY").decimalValue == Decimal(1500))
}

@Test func formattingUsesSymbolsAndCorrectScale() {
    #expect(MoneyFormatter.string(minorUnits: 12345, currencyCode: "CNY") == "¥123.45")
    #expect(MoneyFormatter.string(minorUnits: 1500, currencyCode: "JPY") == "JP¥1,500")
    #expect(MoneyFormatter.string(minorUnits: 120_000_000, currencyCode: "CNY") == "¥1,200,000.00")
    #expect(MoneyFormatter.string(minorUnits: 1234, currencyCode: "CNY", showSymbol: false) == "12.34")
    #expect(MoneyFormatter.string(minorUnits: -1234, currencyCode: "CNY") == "-¥12.34")
}

@Test func totalsNeverMixDifferentCurrencies() {
    let amounts = [
        MoneyAmount(minorUnits: 1000, currencyCode: "CNY"),
        MoneyAmount(minorUnits: 2500, currencyCode: "CNY"),
        MoneyAmount(minorUnits: 1500, currencyCode: "JPY")
    ]

    let totals = MoneyMath.totalsByCurrency(amounts)

    #expect(totals.count == 2)
    #expect(totals[0].currencyCode == "CNY")
    #expect(totals[0].minorUnits == 3500)
    #expect(totals[1].currencyCode == "JPY")
    #expect(totals[1].minorUnits == 1500)
}
