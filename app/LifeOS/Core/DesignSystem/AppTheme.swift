import SwiftUI
import UIKit

// MARK: - Theme

/// 全局语义 token。Sprint V2 起，旧页面也切到 CLASSIFIED 配色。
/// 首页使用更细的 ArchiveTheme；AppTheme 负责其他模块与旧组件。
enum AppTheme {
    // MARK: Backgrounds

    static let background = ArchiveTheme.paper
    static let backgroundElevated = ArchiveTheme.paperTint
    static let surface = ArchiveTheme.paperRaised
    static let surfaceElevated = dynamic(light: 0xFFFDF7, dark: 0x1C2C25)

    // MARK: Ink

    static let textPrimary = ArchiveTheme.ink
    static let textSecondary = ArchiveTheme.inkSoft
    static let textTertiary = ArchiveTheme.inkMuted

    static let separator = ArchiveTheme.rule

    // MARK: Brand

    static let accent = ArchiveTheme.mintDeep
    static let accentDeep = ArchiveTheme.ink
    static let accentSoft = ArchiveTheme.mintWash

    // MARK: Accents

    static let gold = ArchiveTheme.gold
    static let goldBright = dynamic(light: 0xC08F4C, dark: 0xE8C983)
    static let goldSoft = ArchiveTheme.goldWash
    static let coral = ArchiveTheme.coral
    static let indigo = dynamic(light: 0x5B7A83, dark: 0x9CC9CF)
    static let violet = dynamic(light: 0x8A6A7E, dark: 0xD3A9C3)

    static let positive = ArchiveTheme.mintDeep
    static let negative = ArchiveTheme.coral
    static let warning = ArchiveTheme.gold
    static let info = indigo

    // MARK: Metrics

    static let cardRadius: CGFloat = 12
    static let tileRadius: CGFloat = 10
    static let pagePadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 22

    // MARK: Helpers

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func heroGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(hex: 0x1B2A22), Color(hex: 0x0B1511)]
                : [ArchiveTheme.ink, Color(hex: 0x0E2B23)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Typography

extension Font {
    static let lifeDisplay = Font.system(.largeTitle, design: .rounded).weight(.black)
    static let lifeLargeTitle = Font.system(.largeTitle, design: .rounded).weight(.black)
    static let lifeSection = Font.system(.title3, design: .rounded).weight(.bold)
    static let lifeCard = Font.system(.headline, design: .rounded).weight(.bold)
    static let lifeBody = Font.system(.body)
    static let lifeNumber = Font.system(.title, design: .rounded).weight(.black)
    static let lifeFootnote = Font.system(.footnote)
    static let lifeEyebrow = Font.system(size: 9, weight: .semibold, design: .monospaced)
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32, opacity: CGFloat = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: opacity))
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
