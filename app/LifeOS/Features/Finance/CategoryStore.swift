import Foundation
import SwiftUI

// MARK: - Custom categories

struct CustomCategory: Codable, Identifiable, Hashable, Sendable {
    var name: String
    var symbol: String
    var colorHex: UInt32

    var id: String { name }
}

final class CustomCategoryStore: ObservableObject {
    @Published private(set) var categories: [CustomCategory] = []

    private let storageKey = "lifeos.customCategories.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    @discardableResult
    func add(name: String, symbol: String, colorHex: UInt32) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isReserved(trimmed), !categories.contains(where: { $0.name == trimmed }) else {
            return false
        }
        categories.append(CustomCategory(name: trimmed, symbol: symbol, colorHex: colorHex))
        persist()
        return true
    }

    func remove(_ category: CustomCategory) {
        categories.removeAll { $0.id == category.id }
        persist()
    }

    private func isReserved(_ name: String) -> Bool {
        BuiltInCategory.allCases.contains { $0.displayName == name }
            || CategoryCatalog.incomeCategories.contains { $0.name == name }
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CustomCategory].self, from: data) else {
            return
        }
        categories = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(categories) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

// MARK: - Category options

struct CategoryOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let colorHex: UInt32
    let isCustom: Bool

    var color: Color { Color(hex: colorHex) }
}

enum CategoryCatalog {
    static let incomeCategories: [CategoryOption] = [
        CategoryOption(id: "工资", name: "工资", symbol: "banknote.fill", colorHex: 0x9C752F, isCustom: false),
        CategoryOption(id: "红包", name: "红包", symbol: "gift.fill", colorHex: 0xC0573D, isCustom: false),
        CategoryOption(id: "报销", name: "报销", symbol: "doc.text.fill", colorHex: 0x4C5AA6, isCustom: false),
        CategoryOption(id: "理财", name: "理财", symbol: "chart.line.uptrend.xyaxis", colorHex: 0x2E8A6E, isCustom: false),
        CategoryOption(id: "其他收入", name: "其他收入", symbol: "ellipsis.circle.fill", colorHex: 0x8E978F, isCustom: false)
    ]

    static let paletteHexes: [UInt32] = [
        0x9C752F, 0xC0573D, 0x4C5AA6, 0x7A5AA6,
        0x2E8A6E, 0xB65A7A, 0x5E6962, 0x8E978F
    ]

    static let symbolChoices: [String] = [
        "tag.fill", "cart.fill", "fork.knife", "bus.fill",
        "book.fill", "gamecontroller.fill", "cross.case.fill", "house.fill",
        "gift.fill", "airplane", "pawprint.fill", "figure.run"
    ]

    static func expenseOptions(custom: [CustomCategory]) -> [CategoryOption] {
        BuiltInCategory.allCases.map(expenseOption(for:))
            + custom.map {
                CategoryOption(id: $0.name, name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex, isCustom: true)
            }
    }

    static func incomeOptions(custom: [CustomCategory]) -> [CategoryOption] {
        incomeCategories
            + custom.map {
                CategoryOption(id: $0.name, name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex, isCustom: true)
            }
    }

    static func option(for raw: String, kind: TransactionKind, custom: [CustomCategory]) -> CategoryOption {
        if kind == .income {
            if let income = incomeCategories.first(where: { $0.id == raw || $0.name == raw }) {
                return income
            }
            if raw == BuiltInCategory.other.rawValue {
                return incomeCategories.first(where: { $0.id == "其他收入" })
                    ?? CategoryOption(id: "其他收入", name: "其他收入", symbol: "ellipsis.circle.fill", colorHex: 0x8E978F, isCustom: false)
            }
        } else if let builtIn = BuiltInCategory(rawValue: raw) {
            return expenseOption(for: builtIn)
        } else if let byName = BuiltInCategory.allCases.first(where: { $0.displayName == raw }) {
            return expenseOption(for: byName)
        }

        if let customOption = custom.first(where: { $0.name == raw }) {
            return CategoryOption(
                id: customOption.name,
                name: customOption.name,
                symbol: customOption.symbol,
                colorHex: customOption.colorHex,
                isCustom: true
            )
        }

        return CategoryOption(id: raw, name: raw, symbol: "tag.fill", colorHex: 0x8E978F, isCustom: true)
    }

    static func expenseOption(for category: BuiltInCategory) -> CategoryOption {
        let style: (symbol: String, colorHex: UInt32) = switch category {
        case .dining: ("fork.knife", 0xC0573D)
        case .transport: ("bus.fill", 0x4C5AA6)
        case .shopping: ("bag.fill", 0x7A5AA6)
        case .study: ("book.fill", 0x9C752F)
        case .entertainment: ("gamecontroller.fill", 0xB65A7A)
        case .medical: ("cross.case.fill", 0x2E8A6E)
        case .housing: ("house.fill", 0x8A6A4F)
        case .other: ("ellipsis.circle.fill", 0x8E978F)
        }
        return CategoryOption(
            id: category.rawValue,
            name: category.displayName,
            symbol: style.symbol,
            colorHex: style.colorHex,
            isCustom: false
        )
    }
}

// MARK: - Formatting helpers

enum FinanceFormatting {
    static func signedAmount(_ transaction: MoneyTransaction) -> String {
        let absolute = MoneyFormatter.string(
            minorUnits: abs(transaction.amountMinor),
            currencyCode: transaction.currencyCode
        )
        return transaction.kind == .expense ? "-\(absolute)" : "+\(absolute)"
    }

    static func amountColor(for kind: TransactionKind) -> Color {
        kind == .expense ? AppTheme.coral : AppTheme.accent
    }
}

extension PaymentChannel {
    var symbolName: String {
        switch self {
        case .wechat: "message.fill"
        case .alipay: "a.circle.fill"
        case .cash: "banknote.fill"
        case .bankCard: "creditcard.fill"
        case .creditCard: "creditcard"
        case .other: "ellipsis.circle.fill"
        }
    }
}
