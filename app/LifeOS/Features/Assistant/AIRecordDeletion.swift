import Foundation
import SwiftData
import SwiftUI

@MainActor
enum AIRecordDeletion {
    struct Row: Identifiable {
        let id: UUID
        let kind: String
        let title: String
    }
    struct Preview {
        let request: AIRecordDeletionRequest
        let rows: [Row]
    }
    private struct Records {
        var money: [MoneyTransaction] = []
        var study: [StudyTask] = []
        var sessions: [StudySession] = []
        var schedule: [ScheduleTask] = []
    }
    private static func records(_ request: AIRecordDeletionRequest, context: ModelContext) throws -> Records {
        guard let start = AIPlanProposal.localDate(request.date, time: nil),
              let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { throw AIServiceError.invalidResponse }
        var result = Records()
        if request.categories.contains(.finance) {
            result.money = try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.occurredAt >= start && $0.occurredAt < end }))
        }
        if request.categories.contains(.study) {
            result.study = try context.fetch(FetchDescriptor<StudyTask>(predicate: #Predicate { task in
                if let date = task.plannedDate { return date >= start && date < end } else { return false }
            }))
            result.sessions = try context.fetch(FetchDescriptor<StudySession>(predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end }))
        }
        if request.categories.contains(.schedule) {
            result.schedule = try context.fetch(FetchDescriptor<ScheduleTask>(predicate: #Predicate { $0.startAt >= start && $0.startAt < end }))
        }
        return result
    }
    static func preview(_ request: AIRecordDeletionRequest, container: ModelContainer) throws -> Preview {
        let records = try records(request, context: ModelContext(container))
        let rows = records.money.map { Row(id: $0.id, kind: "账目", title: "\($0.merchant.isEmpty ? $0.categoryRaw : $0.merchant) · \($0.currencyCode) \(String(format: "%.2f", Double($0.amountMinor) / 100))") }
            + records.study.map { Row(id: $0.id, kind: "学习任务", title: $0.title) }
            + records.sessions.map { Row(id: $0.id, kind: "专注记录", title: "\($0.taskTitle ?? "专注") · \($0.durationMinutes)分钟") }
            + records.schedule.map { Row(id: $0.id, kind: "日程", title: $0.title) }
        return Preview(request: request, rows: rows)
    }
    /// Deletes only IDs shown in the confirmed preview, still belonging to that day.
    static func delete(_ preview: Preview, container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let records = try records(preview.request, context: context)
        func includes(_ id: UUID, _ kind: String) -> Bool { preview.rows.contains { $0.id == id && $0.kind == kind } }
        var count = 0
        for row in records.money where includes(row.id, "账目") { context.delete(row); count += 1 }
        for row in records.study where includes(row.id, "学习任务") { context.delete(row); count += 1 }
        for row in records.sessions where includes(row.id, "专注记录") { context.delete(row); count += 1 }
        let schedules = records.schedule.filter { includes($0.id, "日程") }
        let notificationIDs = schedules.map(\.id)
        for row in schedules { context.delete(row); count += 1 }
        try context.save()
        for id in notificationIDs { ScheduleNotificationManager.cancel(taskID: id) }
        return count
    }
}

struct AIRecordDeletionReview: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let request: AIRecordDeletionRequest
    let completed: (String) -> Void
    @State private var preview: AIRecordDeletion.Preview?
    @State private var error: String?
    @State private var confirming = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("仅删除 \(request.date) 的所选记录，共 \(preview?.rows.count ?? 0) 条。")
                    Text("账目按付款日期，学习任务按计划日期，专注按开始日期，日程按安排日期。此操作无法在 App 内撤销。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let preview {
                    ForEach(preview.rows) { row in
                        VStack(alignment: .leading) { Text(row.title); Text(row.kind).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("确认按日删除")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("删除", role: .destructive) { confirming = true }.disabled(preview?.rows.isEmpty != false)
                }
            }
            .confirmationDialog("永久删除这 \(preview?.rows.count ?? 0) 条记录？", isPresented: $confirming, titleVisibility: .visible) {
                Button("确认删除 \(request.date) 的记录", role: .destructive) {
                    guard let preview else { return }
                    do {
                        let count = try AIRecordDeletion.delete(preview, container: context.container)
                        completed("已删除 \(request.date) 的 \(count) 条记录。")
                        dismiss()
                    } catch { self.error = "删除失败，未能保存更改，请稍后重试。" }
                }
                Button("取消", role: .cancel) { }
            }
            .task {
                do { preview = try AIRecordDeletion.preview(request, container: context.container) }
                catch { self.error = "无法读取待删除记录，请稍后重试。" }
            }
        }
    }
}
