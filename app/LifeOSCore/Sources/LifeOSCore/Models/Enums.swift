import Foundation

/// 交易类型：支出或收入。
public enum TransactionKind: String, Codable, CaseIterable, Sendable {
    case expense
    case income

    public var displayName: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        }
    }
}

/// 支付渠道。导入账单时会尽量映射到这些渠道，无法识别时归为 other。
public enum PaymentChannel: String, Codable, CaseIterable, Sendable {
    case wechat
    case alipay
    case cash
    case bankCard
    case creditCard
    case other

    public var displayName: String {
        switch self {
        case .wechat: "微信"
        case .alipay: "支付宝"
        case .cash: "现金"
        case .bankCard: "银行卡"
        case .creditCard: "信用卡"
        case .other: "其他"
        }
    }
}

/// 日程优先级。
public enum TaskPriority: Int, Codable, CaseIterable, Comparable, Sendable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3

    public var displayName: String {
        switch self {
        case .low: "低"
        case .normal: "普通"
        case .high: "高"
        case .urgent: "紧急"
        }
    }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 学习计时类型。
public enum StudySessionKind: String, Codable, CaseIterable, Sendable {
    case focus
    case shortBreak
    case longBreak

    public var displayName: String {
        switch self {
        case .focus: "专注"
        case .shortBreak: "短休息"
        case .longBreak: "长休息"
        }
    }
}

/// 内置支出分类。自定义分类会以原始字符串形式保存在交易记录中。
public enum BuiltInCategory: String, Codable, CaseIterable, Sendable {
    case dining
    case transport
    case shopping
    case study
    case entertainment
    case medical
    case housing
    case other

    public var displayName: String {
        switch self {
        case .dining: "餐饮"
        case .transport: "交通"
        case .shopping: "购物"
        case .study: "学习"
        case .entertainment: "娱乐"
        case .medical: "医疗"
        case .housing: "居住"
        case .other: "其他"
        }
    }

    public var symbolName: String {
        switch self {
        case .dining: "fork.knife"
        case .transport: "bus.fill"
        case .shopping: "bag.fill"
        case .study: "book.fill"
        case .entertainment: "gamecontroller.fill"
        case .medical: "cross.case.fill"
        case .housing: "house.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}
