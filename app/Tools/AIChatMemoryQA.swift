import Foundation

@main struct AIChatMemoryQA {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lifeos-memory-qa-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("lifeos-ai-conversation-v1.json")
        let sentence = "星期三第一至八节有课，晚上十一点二十睡觉，每天英语词汇复习三次。"
        let original = (0..<1000).map { AIChatLine(role: $0 % 2 == 0 ? .user : .assistant, text: "第\($0)条：" + sentence + String(repeating: sentence, count: 5), attachmentLabel: $0 == 3 ? "合成文件.txt" : nil) }
        let raw = try JSONEncoder().encode(original)
        try raw.write(to: legacy)
        let loaded = try AIChatHistory.load(in: directory)
        precondition(loaded.map(\.id) == original.map(\.id) && loaded.map(\.text) == original.map(\.text))
        precondition(loaded.map(\.createdAt) == original.map(\.createdAt) && loaded[3].attachmentLabel == "合成文件.txt")
        precondition(tryData(legacy) == raw, "legacy migration backup changed")
        let info = try AIChatHistory.info(in: directory)
        precondition(info.messages == 1000 && info.bytes < raw.count / 2, "archive did not compact fixture")
        let updated = loaded + [AIChatLine(role: .user, text: "从今天起改成23:00睡觉")]
        try AIChatHistory.save(updated, in: directory)
        let reopened = try AIChatHistory.load(in: directory)
        precondition(reopened.count == 1001 && reopened.last!.text == updated.last!.text)
        let positions = AIHistoryRetrieval.matchingIndices("睡眠安排", in: reopened.map(\.memoryMessage))
        precondition(positions.contains(1000), "reopened memory not searchable")
        let file = try AIChatHistory.url(in: directory)
        let good = try Data(contentsOf: file)
        try Data(good.prefix(49)).write(to: file)
        do { _ = try AIChatHistory.load(in: directory); fatalError("empty compressed payload accepted") }
        catch is CocoaError {}
        var badChecksum = good
        badChecksum[17] ^= 1
        try badChecksum.write(to: file)
        do { _ = try AIChatHistory.load(in: directory); fatalError("corrupt checksum accepted") }
        catch is CocoaError {}
        try Data("broken archive".utf8).write(to: file)
        do { _ = try AIChatHistory.load(in: directory); fatalError("corrupt archive fell back to obsolete history") }
        catch is CocoaError {}
        try good.write(to: file)
        try AIChatHistory.save([], in: directory)
        let cleared = try AIChatHistory.load(in: directory)
        precondition(cleared.isEmpty, "clear resurrected legacy messages")
        precondition(tryData(legacy) == Data("[]".utf8), "clear retained legacy private messages")
        try FileManager.default.removeItem(at: file)
        let remigrated = try AIChatHistory.load(in: directory)
        precondition(remigrated.isEmpty, "missing new file resurrected cleared migration backup")
        print("Memory QA passed: legacy migration, exact IDs/dates/text, append/reopen/search, corruption, clear. Synthetic1000 messages: \(raw.count) -> \(info.bytes) bytes.")
    }
    private static func tryData(_ url: URL) -> Data { (try? Data(contentsOf: url)) ?? Data() }
}
