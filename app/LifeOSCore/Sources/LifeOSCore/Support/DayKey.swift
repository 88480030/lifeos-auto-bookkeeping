import Foundation

/// 日期键工具。统一按传入的 Calendar（含时区）计算，避免跨时区统计错位。
public enum DayKey {
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    public static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    public static func startOfDay(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func dayInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
    }
}
