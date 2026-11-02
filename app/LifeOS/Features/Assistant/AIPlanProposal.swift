import Foundation

/// Untrusted model output is validated before it can be presented or saved.
struct AIPlanProposal: Codable, Sendable {
    struct Item: Codable, Sendable, Identifiable {
        let id: UUID
        let kind: Kind
        let title: String
        let subject: String
        let date: String?
        let time: String?
        let minutes: Int
        enum Kind: String, Codable, Sendable { case study, schedule }
    }
    let items: [Item]

    static func parse(_ json: String) -> AIPlanProposal? {
        guard json.utf8.count <= 60_000, let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["items"], let raw = root["items"] as? [[String: Any]],
              (1...200).contains(raw.count) else { return nil }
        var result: [Item] = []
        for entry in raw {
            guard Set(entry.keys).isSubset(of: ["kind", "title", "subject", "date", "time", "minutes"]),
                  let kindText = entry["kind"] as? String, let kind = Item.Kind(rawValue: kindText),
                  let rawTitle = entry["title"] as? String,
                  let minutes = entry["minutes"] as? Int, (1...1440).contains(minutes) else { return nil }
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = (entry["subject"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 120, subject.count <= 80 else { return nil }
            let date = entry["date"] as? String
            let time = entry["time"] as? String
            if let date, localDate(date, time: time) == nil { return nil }
            if time != nil && date == nil { return nil }
            if kind == .schedule && (date == nil || time == nil) { return nil }
            result.append(Item(id: UUID(), kind: kind, title: title, subject: subject, date: date, time: time, minutes: minutes))
        }
        return AIPlanProposal(items: result)
    }

    static func localDate(_ date: String, time: String?) -> Date? {
        let value = date + " " + (time ?? "00:00")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.isLenient = false
        guard let parsed = f.date(from: value), f.string(from: parsed) == value else { return nil }
        return parsed
    }
}

/// A model can propose a single-day deletion; only the local confirmation UI executes it.
struct AIRecordDeletionRequest: Codable, Sendable {
    let date: String
    let categories: [AIReadCategory]
    static func parse(_ text: String) -> AIRecordDeletionRequest? {
        guard text.utf8.count <= 2000,
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              Set(object.keys) == ["date", "categories"],
              let date = object["date"] as? String, AIPlanProposal.localDate(date, time: nil) != nil,
              let names = object["categories"] as? [String], !names.isEmpty, names.count <= 3 else { return nil }
        let categories = names.compactMap(AIReadCategory.init(rawValue:))
        guard categories.count == names.count, Set(categories).count == categories.count,
              !categories.contains(.settings) else { return nil }
        return Self(date: date, categories: categories)
    }
}

struct AIStudyEditRequest: Sendable {
    struct Item: Sendable {
        let date: String
        let oldTitle: String
        let newTitle: String
        let subject: String?
        var newDate: String? = nil
        var minutes: Int? = nil
        var time: String? = nil
    }
    let items: [Item]
    static func parse(_ text: String) -> Self? {
        guard text.utf8.count <= 60_000,
              let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              Set(root.keys) == ["items"], let rows = root["items"] as? [[String: Any]], (1...50).contains(rows.count) else { return nil }
        var result: [Item] = []
        for row in rows {
            guard Set(row.keys).isSubset(of: ["date", "old_title", "new_title", "subject", "new_date", "minutes", "time"]),
                  let date = row["date"] as? String, (date.isEmpty || AIPlanProposal.localDate(date, time: nil) != nil),
                  let old = row["old_title"] as? String, !old.isEmpty, old.count <= 120,
                  let new = row["new_title"] as? String, !new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, new.count <= 120,
                  row["subject"] == nil || (row["subject"] as? String).map({ $0.count <= 80 }) == true else { return nil }
            let newDate = row["new_date"] as? String
            let minutes = row["minutes"] as? Int
            let time = row["time"] as? String
            if row["time"] != nil && (time == nil || (!time!.isEmpty && AIPlanProposal.localDate("2026-01-01", time: time) == nil)) { return nil }
            guard row["new_date"] == nil || (newDate != nil && (newDate!.isEmpty || AIPlanProposal.localDate(newDate!, time: nil) != nil)),
                  row["minutes"] == nil || (minutes != nil && (1...1440).contains(minutes!)) else { return nil }
            result.append(.init(date: date, oldTitle: old, newTitle: new, subject: row["subject"] as? String, newDate: newDate, minutes: minutes, time: time))
        }
        return Self(items: result)
    }
}

/// A scoped, reversible replacement of one study topic, never an entire day.
struct AIStudyTopicReplacementRequest: Codable, Sendable {
    struct Item: Codable, Sendable {
        let title: String
        let subject: String
        let date: String
        let time: String?
        let minutes: Int
    }
    let startDate: String
    let endDate: String // exclusive
    let titleContains: String
    let dailyCount: Int?
    let items: [Item]

    static func parse(_ json: String) -> Self? {
        guard json.utf8.count <= 60_000, let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              Set(root.keys).isSubset(of: ["start_date", "end_date", "title_contains", "daily_count", "items"]),
              let start = root["start_date"] as? String, let end = root["end_date"] as? String,
              let from = AIPlanProposal.localDate(start, time: nil), let to = AIPlanProposal.localDate(end, time: nil),
              from < to, let dayCount = Calendar.current.dateComponents([.day], from: from, to: to).day,
              (1...90).contains(dayCount),
              let rawTopic = root["title_contains"] as? String else { return nil }
        let topic = rawTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(topic.count), let rows = root["items"] as? [[String: Any]],
              (1...200).contains(rows.count) else { return nil }
        let dailyCount = root["daily_count"] as? Int
        guard root["daily_count"] == nil || dailyCount == 1 else { return nil }
        var result: [Item] = []
        for row in rows {
            guard Set(row.keys).isSubset(of: ["title", "subject", "date", "time", "minutes"]),
                  let title = row["title"] as? String, title.contains(topic), (1...200).contains(title.count),
                  let subject = row["subject"] as? String, subject.count <= 100,
                  let date = row["date"] as? String, let day = AIPlanProposal.localDate(date, time: nil), day >= from, day < to,
                  let minutes = row["minutes"] as? Int, (1...1440).contains(minutes) else { return nil }
            let time = row["time"] as? String
            guard row["time"] == nil || (time != nil && AIPlanProposal.localDate(date, time: time) != nil) else { return nil }
            result.append(Item(title: title, subject: subject, date: date, time: time, minutes: minutes))
        }
        if dailyCount == 1 {
            guard result.count == dayCount, Set(result.map(\.date)).count == dayCount else { return nil }
        }
        return Self(startDate: start, endDate: end, titleContains: topic, dailyCount: dailyCount, items: result)
    }
}
