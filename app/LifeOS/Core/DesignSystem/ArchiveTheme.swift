import SwiftUI
import UIKit

/// LifeOS「CLASSIFIED」视觉系统的语义 token。
/// 现有页面仍使用 AppTheme；Sprint V1 只让首页和 Tab Bar 使用 ArchiveTheme。
enum ArchiveTheme {
    // MARK: - Paper & ink

    static let paper = dynamic(light: 0xF6F0E2, dark: 0x0D1713)
    static let paperRaised = dynamic(light: 0xFFFBF1, dark: 0x17241E)
    static let paperTint = dynamic(light: 0xEFE7D7, dark: 0x101D17)
    static let paperDeep = dynamic(light: 0xE8DECC, dark: 0x0A120F)

    static let ink = dynamic(light: 0x16382F, dark: 0xF3EEE3)
    static let inkSoft = dynamic(light: 0x4D655B, dark: 0xB8C8BE)
    static let inkMuted = dynamic(light: 0x7A8A80, dark: 0x83968B)

    // MARK: - Archive accents

    static let mint = dynamic(light: 0xBFE0CF, dark: 0x8FC9AD)
    static let mintDeep = dynamic(light: 0x4E8E77, dark: 0x7ECAA9)
    static let mintWash = dynamic(light: 0xE5F1E9, dark: 0x15271F)
    static let sage = dynamic(light: 0xA9C6B9, dark: 0x355B4B)
    static let sageDeep = dynamic(light: 0x7FA796, dark: 0x4E7D68)
    static let sageWash = dynamic(light: 0xDCEBE4, dark: 0x172A22)
    static let pink = dynamic(light: 0xF1C6CE, dark: 0xE5A9B7)
    static let pinkWash = dynamic(light: 0xFAEDEF, dark: 0x2A1B20)
    static let gold = dynamic(light: 0xA97C3F, dark: 0xD6B16E)
    static let goldWash = dynamic(light: 0xF3E8D3, dark: 0x2A2215)
    static let coral = dynamic(light: 0xC0604A, dark: 0xE8846F)
    static let stamp = dynamic(light: 0xB24B43, dark: 0xE07A70)
    static let strip = dynamic(light: 0x16382F, dark: 0x1B2A22)
    static let stripInk = dynamic(light: 0xFFFBF1, dark: 0xF3EEE3)

    // Reminders smart lists: white labels on blue Today / red Scheduled tiles.
    static let reminderToday = dynamic(light: 0x578FD8, dark: 0x427CC8)
    static let reminderTodayEnd = dynamic(light: 0x3979CA, dark: 0x2D65B0)
    static let reminderScheduled = dynamic(light: 0xDF727B, dark: 0xCB616B)
    static let reminderScheduledEnd = dynamic(light: 0xD55965, dark: 0xB74754)
    static let reminderSelection = dynamic(light: 0x55616B, dark: 0x929AA4)

    // MARK: - Rules & depth

    static let rule = dynamic(light: 0xD9CEB8, dark: 0x2D3D34)
    static let ruleStrong = dynamic(light: 0xC7B99F, dark: 0x40574A)
    static let shadow = dynamic(light: 0x17241E, dark: 0x000000)

    // MARK: - Metrics

    static let pagePadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 26
    static let sheetRadius: CGFloat = 22
    static let tileRadius: CGFloat = 14
    static let tabRadius: CGFloat = 9

    // MARK: - Helpers

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func paperShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.black.opacity(0.38)
            : shadow.opacity(0.075)
    }
}

// MARK: - Typography

extension Font {
    /// 日期、金额、封面级标题。
    static let archiveDisplay = Font.system(.largeTitle, design: .serif).weight(.semibold)
    /// 档案标题、下一项任务标题。
    static let archiveTitle = Font.system(.title3, design: .serif).weight(.semibold)
    /// 区块标题。
    static let archiveSection = Font.system(.headline).weight(.semibold)
    static let archiveBody = Font.system(.body)
    static let archiveCaption = Font.system(.caption)
    /// 档案编号、状态、页码：只作为元信息，不承担正文。
    static let archiveMono = Font.system(.caption2, design: .monospaced).weight(.medium)
    static let archiveMonoStrong = Font.system(.caption, design: .monospaced).weight(.semibold)
}
