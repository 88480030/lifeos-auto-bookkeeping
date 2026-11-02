#if DEBUG
import Foundation
import SwiftData

/// 仅用于开发期 UI 评估与截图：在模拟器里灌入一批真实结构的测试记录。
/// 由启动参数 `-seedPreviewData` 触发，不会出现在 Release 构建中，也不会被真实用户看到。
@MainActor
enum PreviewDataSeeder {
    static func seedIfNeeded(in container: ModelContainer) {
        let context = ModelContext(container)

        let transactionCount = (try? context.fetchCount(FetchDescriptor<MoneyTransaction>())) ?? 0
        let taskCount = (try? context.fetchCount(FetchDescriptor<ScheduleTask>())) ?? 0
        let sessionCount = (try? context.fetchCount(FetchDescriptor<StudySession>())) ?? 0
        guard transactionCount == 0, taskCount == 0, sessionCount == 0 else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        func date(_ hour: Int, _ minute: Int, offsetDays: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: offsetDays, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let transactions: [(Int, String, TransactionKind, BuiltInCategory, PaymentChannel, Date, String, String)] = [
            (2800, "CNY", .expense, .dining, .wechat, date(8, 15), "早餐 · 手冲咖啡", "M Stand"),
            (4250, "CNY", .expense, .dining, .alipay, date(12, 5), "午餐", "松屋"),
            (3600, "CNY", .expense, .transport, .wechat, date(16, 20), "打车回家", "滴滴出行"),
            (1500, "JPY", .expense, .dining, .cash, date(11, 30), "便利店咖啡", "7-Eleven"),
            (20000, "CNY", .income, .other, .wechat, date(9, 40), "朋友转账", ""),
            (5800, "CNY", .expense, .study, .bankCard, date(20, 30, offsetDays: -1), "技术书", "京东")
        ]

        for item in transactions {
            let transaction = MoneyTransaction(
                amountMinor: item.0,
                currencyCode: item.1,
                kind: item.2,
                categoryRaw: item.3.rawValue,
                channel: item.4,
                occurredAt: item.5,
                note: item.6,
                merchant: item.7
            )
            if item.2 == .income {
                transaction.categoryRaw = "其他收入"
            }
            context.insert(transaction)
        }

        let sessions: [(Int, Int, Int, String, String)] = [
            (9, 0, 25, "阅读《深度工作》", "阅读"),
            (9, 35, 25, "阅读《深度工作》", "阅读"),
            (14, 0, 25, "复习英语单词", "英语")
        ]

        for item in sessions {
            let start = date(item.0, item.1)
            let end = start.addingTimeInterval(TimeInterval(item.2 * 60))
            context.insert(
                StudySession(
                    startedAt: start,
                    endedAt: end,
                    focusedSeconds: item.2 * 60,
                    kind: .focus,
                    taskTitle: item.3,
                    subject: item.4
                )
            )
        }

        let history: [(dayOffset: Int, hour: Int, minute: Int, minutes: Int, task: String, subject: String)] = [
            (1, 20, 0, 25, "阅读《深度工作》", "阅读"),
            (1, 21, 0, 25, "复习英语单词", "英语"),
            (2, 19, 30, 50, "数学练习", "数学"),
            (3, 20, 0, 25, "复习英语单词", "英语"),
            (4, 19, 0, 25, "编程练习", "编程"),
            (4, 20, 0, 25, "阅读《深度工作》", "阅读"),
            (5, 20, 0, 50, "数学练习", "数学"),
            (6, 20, 0, 25, "阅读《深度工作》", "阅读"),
            (8, 20, 0, 50, "编程练习", "编程")
        ]

        for item in history {
            let start = date(item.hour, item.minute, offsetDays: -item.dayOffset)
            let end = start.addingTimeInterval(TimeInterval(item.minutes * 60))
            context.insert(
                StudySession(
                    startedAt: start,
                    endedAt: end,
                    focusedSeconds: item.minutes * 60,
                    kind: .focus,
                    taskTitle: item.task,
                    subject: item.subject
                )
            )
        }

        let scheduleItems: [(String, Int, Int, Int, TaskPriority, Bool, String)] = [
            ("晨间阅读", 10, 0, 30, .high, true, "25 分钟专注 + 写 5 行笔记"),
            ("复习英语单词", 14, 0, 30, .normal, true, ""),
            ("健身房训练", 18, 30, 60, .high, false, "推 + 拉，注意热身"),
            ("每日复盘", 21, 0, 20, .low, false, "记录今天的三件事")
        ]

        for item in scheduleItems {
            context.insert(
                ScheduleTask(
                    title: item.0,
                    startAt: date(item.1, item.2),
                    durationMinutes: item.3,
                    priority: item.4,
                    isCompleted: item.5,
                    notes: item.6,
                    reminderMinutesBefore: 10
                )
            )
        }

        // 未来一周 / 本月的日程，用于周视图、月视图和日历圆点。
        let upcomingSchedule: [(dayOffset: Int, hour: Int, minute: Int, minutes: Int, title: String, priority: TaskPriority)] = [
            (1, 9, 0, 60, "项目规划", .high),
            (1, 19, 0, 45, "晚间散步", .low),
            (2, 19, 0, 90, "英语角", .normal),
            (3, 8, 0, 30, "晨跑", .normal),
            (5, 14, 0, 45, "整理房间", .low),
            (7, 20, 0, 30, "周复盘", .high),
            (-2, 18, 0, 30, "旧日程", .normal)
        ]

        for item in upcomingSchedule {
            context.insert(
                ScheduleTask(
                    title: item.title,
                    startAt: date(item.hour, item.minute, offsetDays: item.dayOffset),
                    durationMinutes: item.minutes,
                    priority: item.priority,
                    notes: "",
                    reminderMinutesBefore: item.dayOffset > 0 ? 10 : nil
                )
            )
        }

        // 重复任务示例：未来 7 天的晨间阅读。
        let morningSeriesID = "demo-morning-reading"
        for offset in 1...7 {
            context.insert(
                ScheduleTask(
                    title: "晨间阅读",
                    startAt: date(7, 30, offsetDays: offset),
                    durationMinutes: 25,
                    priority: .normal,
                    notes: "重复任务示例",
                    reminderMinutesBefore: 5,
                    repeatRuleRaw: RepeatRule.daily.rawValue,
                    seriesID: morningSeriesID
                )
            )
        }

        context.insert(
            StudyTask(
                title: "阅读《深度工作》",
                subject: "阅读",
                estimatedMinutes: 50,
                plannedDate: today,
                isCompleted: true,
                completedAt: date(9, 55)
            )
        )
        context.insert(
            StudyTask(
                title: "复习英语单词",
                subject: "英语",
                estimatedMinutes: 25,
                plannedDate: today,
                isCompleted: false
            )
        )

        context.insert(
            StudyTask(
                title: "整理数学错题",
                subject: "数学",
                estimatedMinutes: 40,
                plannedDate: today,
                isCompleted: false
            )
        )
        context.insert(
            StudyTask(
                title: "背 50 个单词",
                subject: "英语",
                estimatedMinutes: 30,
                plannedDate: today,
                isCompleted: false
            )
        )

        // 本月历史记录：让日历与统计图表有真实可看的分布。
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: today)
        ) ?? today

        func monthDate(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            let dayDate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayDate) ?? dayDate
        }

        let monthRecords: [(day: Int, hour: Int, minute: Int, yuan: Int, category: BuiltInCategory, channel: PaymentChannel, note: String)] = [
            (3, 9, 20, 32, .dining, .wechat, "咖啡"),
            (3, 19, 10, 157, .shopping, .alipay, "超市采购"),
            (5, 8, 45, 6, .transport, .alipay, "地铁"),
            (5, 12, 30, 39, .dining, .wechat, "午餐"),
            (8, 20, 15, 299, .shopping, .bankCard, "换季外套"),
            (10, 15, 0, 45, .entertainment, .alipay, "电影票"),
            (10, 16, 30, 18, .dining, .wechat, "奶茶"),
            (12, 10, 0, 36, .medical, .cash, "感冒药"),
            (15, 9, 0, 1500, .housing, .bankCard, "房租"),
            (18, 21, 20, 89, .study, .alipay, "技术书"),
            (20, 19, 30, 128, .dining, .wechat, "朋友聚餐"),
            (22, 8, 10, 24, .transport, .wechat, "打车"),
            (22, 9, 0, 28, .dining, .wechat, "咖啡")
        ]

        for item in monthRecords {
            context.insert(
                MoneyTransaction(
                    amountMinor: item.yuan * 100,
                    currencyCode: "CNY",
                    kind: .expense,
                    categoryRaw: item.category.rawValue,
                    channel: item.channel,
                    occurredAt: monthDate(item.day, item.hour, item.minute),
                    note: item.note
                )
            )
        }

        context.insert(
            MoneyTransaction(
                amountMinor: 1_800_000,
                currencyCode: "CNY",
                kind: .income,
                categoryRaw: "工资",
                channel: .bankCard,
                occurredAt: monthDate(1, 9, 0),
                note: "本月工资"
            )
        )
        context.insert(
            MoneyTransaction(
                amountMinor: 20_000,
                currencyCode: "CNY",
                kind: .income,
                categoryRaw: "红包",
                channel: .wechat,
                occurredAt: monthDate(15, 20, 0),
                note: "朋友红包"
            )
        )
        context.insert(
            MoneyTransaction(
                amountMinor: 4_800,
                currencyCode: "JPY",
                kind: .expense,
                categoryRaw: BuiltInCategory.dining.rawValue,
                channel: .cash,
                occurredAt: monthDate(12, 13, 0),
                note: "日本午餐"
            )
        )

        context.insert(
            Budget(
                monthKey: DayKey.monthKey(for: .now),
                amountMinor: 300_000,
                currencyCode: "CNY"
            )
        )

        try? context.save()
    }
}
#endif
