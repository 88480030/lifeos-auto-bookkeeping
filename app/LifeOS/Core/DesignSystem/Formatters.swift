import Foundation

@MainActor
enum AppFormatters {
    private static let timeFormatter = makeFormatter("HH:mm")
    private static let dateHeaderFormatter = makeFormatter("M月d日 EEEE")
    private static let shortDateFormatter = makeFormatter("M月d日")
    private static let monthDayFormatter = makeFormatter("M月d日")
    private static let monthTitleFormatter = makeFormatter("yyyy年M月")
    private static let dateTimeFormatter = makeFormatter("M月d日 EEEE HH:mm")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }

    static func greeting(for date: Date = .now) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<9: return "早上好"
        case 9..<12: return "上午好"
        case 12..<14: return "中午好"
        case 14..<18: return "下午好"
        default: return "晚上好"
        }
    }

    static func dateHeader(_ date: Date = .now) -> String {
        dateHeaderFormatter.string(from: date)
    }

    static func monthDay(_ date: Date = .now) -> String {
        monthDayFormatter.string(from: date)
    }

    static func monthTitle(_ date: Date = .now) -> String {
        monthTitleFormatter.string(from: date)
    }

    static func weekdayEnglish(_ date: Date = .now) -> String {
        let names = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
        let index = Calendar.current.component(.weekday, from: date) - 1
        return names[max(0, min(index, names.count - 1))]
    }

    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func timeRange(start: Date, end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }

    static func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    static func duration(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) 分钟"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) 小时" : "\(hours) 小时 \(remainder) 分钟"
    }

    static func studyDuration(seconds: Int) -> String {
        if seconds <= 0 {
            return "0 分钟"
        }
        if seconds < 60 {
            return "不足 1 分钟"
        }
        return duration(minutes: seconds / 60)
    }

    static func percent(_ ratio: Double) -> String {
        "\(Int((min(max(ratio, 0), 1) * 100).rounded()))%"
    }

    static func currency(minorUnits: Int, currencyCode: String) -> String {
        MoneyFormatter.string(minorUnits: minorUnits, currencyCode: currencyCode)
    }
}
