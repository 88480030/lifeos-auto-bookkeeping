import Foundation

private struct RetrievalFailure: Error, CustomStringConvertible {
    let description: String
}

@main struct AIHistoryRetrievalQA {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw RetrievalFailure(description: message) }
    }

    static func main() throws {
        let history: [AIServiceMessage] = [
            .init(role: .user, content: "[2026-10-27] 我晚上十一点二十睡觉，早上七点起床。"),
            .init(role: .assistant, content: "你可以选择晚上十点睡觉。"),
            .init(role: .user, content: "[2026-10-28] 星期三第一节到第八节都有课，每节45分钟，中间休息10分钟。"),
            .init(role: .assistant, content: "建议你周三下午安排刷题。"),
            .init(role: .user, content: "[2026-10-29] 改一下，我以后晚上十一点睡觉。"),
            .init(role: .user, content: "今天午饭吃面条。")
        ]
        let sleep = AIHistoryRetrieval.search("我的就寝时间是什么", in: history)
        try require(sleep.first?.content.contains("以后晚上十一点睡觉") == true,
                    "sleep paraphrase must retrieve latest user statement before assistant suggestions")
        let courses = AIHistoryRetrieval.search("之前的课程安排", in: history)
        try require(courses.contains { $0.content.contains("第一节到第八节") },
                    "course paraphrase must find a user schedule even when only single Chinese 课 matches")
        let weekdays: [AIServiceMessage] = [
            .init(role: .user, content: "星期三第一节到第八节都有课"),
            .init(role: .user, content: "周五第七节第八节上课")
        ]
        try require(AIHistoryRetrieval.search("周三课表", in: weekdays).first?.content.contains("星期三") == true,
                    "weekday alias must distinguish Wednesday from more recent Friday class")
        try require(AIHistoryRetrieval.search("量子物理实验", in: history).isEmpty,
                    "unrelated query must not return arbitrary recent history")
        try require(AIHistoryRetrieval.search("谢谢你", in: history).isEmpty,
                    "nonempty filler query must not dump arbitrary history")
        try require(AIHistoryRetrieval.search("", in: history).count == history.count,
                    "explicit empty query must still support chronological browsing")

        let duplicate: [AIServiceMessage] = [
            .init(role: .user, content: "我每天背英语单词"),
            .init(role: .assistant, content: "旧回复"),
            .init(role: .user, content: "我每天背英语单词"),
            .init(role: .assistant, content: "新回复")
        ]
        let page = try JSONSerialization.jsonObject(with: Data(AIHistoryRetrieval.payload("英语", history: duplicate).utf8)) as! [String: Any]
        let rows = page["matches"] as! [[String: String]]
        try require(rows.first?["source"] == "history-2" && rows.first?["adjacentContext"]?.contains("新回复") == true,
                    "duplicate text must retain real source position and adjacent reply")
        let prior = AIHistoryRetrieval.search("猫咪名字", in: [.init(role: .user, content: "我的猫叫阿福")])
        let later = AIHistoryRetrieval.search("猫咪名字", in: [.init(role: .user, content: "我的猫叫阿花")])
        try require(prior.first?.content.contains("阿福") == true && later.first?.content.contains("阿花") == true,
                    "index cache must invalidate after same-count source edits")
        let longRoutine = [AIServiceMessage(role: .user, content: "[2026-10-29T08:00:00+08:00] " + String(repeating: "这是课程之外的说明。", count: 250) + "我每天晚上23:20睡觉，早晨07:00起床。")]
        let routinePage = try AIHistoryRetrieval.payload("我的作息", history: longRoutine)
        try require(routinePage.contains("23:20睡觉"), "long topic recall must center its excerpt on a real matching fact")

        let benchmarkHistory = (0..<1000).map { index in
            AIServiceMessage(role: index % 2 == 0 ? .user : .assistant,
                             content: "[2026-10-29] 记录\(index)：" + String(repeating: "英语学习每天背单词，星期三上课，晚上十一点睡觉。", count: 8))
        }
        var began = Date.timeIntervalSinceReferenceDate
        let cold = AIHistoryRetrieval.makeIndex(for: benchmarkHistory)
        let coldMilliseconds = (Date.timeIntervalSinceReferenceDate - began) * 1000
        began = Date.timeIntervalSinceReferenceDate
        _ = AIHistoryRetrieval.makeIndex(for: benchmarkHistory)
        let warmMilliseconds = (Date.timeIntervalSinceReferenceDate - began) * 1000
        let appended = benchmarkHistory + [AIServiceMessage(role: .user, content: "补充：我的猫叫小福，周五下午健身。")]
        began = Date.timeIntervalSinceReferenceDate
        let expanded = AIHistoryRetrieval.makeIndex(for: appended)
        let appendMilliseconds = (Date.timeIntervalSinceReferenceDate - began) * 1000
        try require(cold.count == 1000 && expanded.count == 1001 && expanded.isCurrent(for: appended), "appended index must include new source fingerprint")
        try require(AIHistoryRetrieval.matchingIndices("猫咪名字", in: appended).first == 1000, "new appended memory must be retrievable immediately")
        print(String(format: "1000-message index benchmark ms: cold=%.1f warm=%.1f append=%.1f", coldMilliseconds, warmMilliseconds, appendMilliseconds))
        print("History retrieval checks passed: paraphrases, latest user, unrelated misses, duplicate sources, edit invalidation")
    }
}
