import SwiftUI

struct AIConversationMemoryView: View {
    @Environment(\.dismiss) private var dismiss
    let lines: [AIChatLine]
    @State private var query = ""
    @State private var includeAssistant = false
    @State private var matches: [Int] = []
    @State private var searching = true
    @State private var info: AIChatHistory.StorageInfo?
    @State private var storageError: String?
    @State private var visibleCount = 20

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("自动保存 \(lines.count) 条对话", systemImage: "brain")
                    if let info {
                        Text("压缩文件 \(ByteCountFormatter.string(fromByteCount: Int64(info.bytes), countStyle: .file)) · 原文 \(ByteCountFormatter.string(fromByteCount: Int64(info.originalBytes), countStyle: .file))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("原话无损压缩保存，索引指向原文，不复制整份对话。搜索支持关键词和常见主题，如作息、课表、健身；不会把 AI 的建议当成你已确认的安排。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("同时查看 AI 回复", isOn: $includeAssistant)
                }
                Section(query.isEmpty ? "最近的原话" : "匹配 \(matches.count) 条原话") {
                    if searching { ProgressView("正在检索本机记忆…") }
                    else if matches.isEmpty {
                        Text(lines.isEmpty ? "开始对话后，原话会自动保存在这里。" : "没有匹配到原话，试试更短的关键词，或清空搜索查看全部对话。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(matches.prefix(visibleCount)), id: \.self) { position in
                        let line = lines[position]
                        NavigationLink {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text(line.createdAt, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                    Text(line.text).textSelection(.enabled)
                                    let adjacent = line.role == .user ? position + 1 : position - 1
                                    if lines.indices.contains(adjacent), lines[adjacent].role != line.role {
                                        Divider()
                                        Text(lines[adjacent].role == .user ? "相邻用户原话" : "相邻 AI 回复 · 不代表已确认").font(.headline)
                                        Text(lines[adjacent].text).textSelection(.enabled)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                            }.navigationTitle("记忆原文").navigationBarTitleDisplayMode(.inline)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(line.role == .user ? "你的原话" : "AI 回复 · 不代表已确认")
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Text(line.createdAt, format: .dateTime.month().day().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(String(line.text.prefix(600))).font(.subheadline).lineLimit(8)
                                Text("查看完整原文与相邻对话").font(.caption).foregroundStyle(.secondary)
                                if let name = line.attachmentLabel { Text("附件名称：" + name).font(.caption).foregroundStyle(.secondary) }
                            }.padding(.vertical, 5)
                        }
                    }
                    if matches.count > visibleCount {
                        Button("再显示 20 条") { visibleCount += 20 }
                    }
                }
                if let storageError { Section { Text(storageError).font(.footnote).foregroundStyle(.red) } }
                Section {
                    Text("仅搜索本机，不调用 AI，也不消耗 API 额度。缓存不保存照片、视频或文件本体。升级时保留一份旧版原始记录作为迁移备份；清空本机对话也会清空它和这些记忆。手动填写的需求与偏好独立保留。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("自动记忆缓存")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜作息、课表、目标或原话")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task {
                guard !lines.isEmpty else { return }
                do { info = try await Task.detached(priority: .utility) { try AIChatHistory.info() }.value }
                catch { storageError = "无法读取存储状态，请解锁设备后重试；原记录未覆盖。" }
            }
            .task(id: query + (includeAssistant ? "|all" : "|user")) {
                searching = true
                let text = query
                let all = includeAssistant
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                let result = await Task.detached(priority: .userInitiated) {
                    AIHistoryRetrieval.matchingIndices(text, in: lines.map(\.memoryMessage))
                        .filter { all || lines[$0].role == .user }
                }.value
                guard !Task.isCancelled else { return }
                matches = result
                visibleCount = 20
                searching = false
            }
        }
    }
}
