import PhotosUI
import SwiftUI

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lifeos.appearance") private var appearance = "system"
    @AppStorage("lifeos.haptics") private var hapticsEnabled = true
    @ObservedObject private var artwork = MiraArtStore.shared
    @State private var photoItem: PhotosPickerItem?
    @State private var importing = false
    @State private var artworkError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("使用偏好") {
                    Picker("外观", selection: $appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色纸张").tag("light")
                        Text("深色档案").tag("dark")
                    }
                    Toggle("触感反馈", isOn: $hapticsEnabled)
                }
                Section {
                    HStack(spacing: 14) {
                        MangaCharacterImage(expression: .neutral, width: 56, height: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("你的情报官").font(.headline)
                            Text(artwork.customImage == nil ? "使用内置立绘" : "使用本机导入的立绘")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("从相册更换立绘", systemImage: "photo.badge.plus")
                            .frame(minHeight: 44)
                    }
                    .disabled(importing)
                    if importing { ProgressView("正在导入…") }
                    if artwork.customImage != nil {
                        Button("恢复内置立绘") { artwork.reset() }
                            .frame(minHeight: 44)
                    }
                } header: {
                    Text("角色立绘")
                } footer: {
                    Text("内置角色支持互动动作；导入图片以静态立绘展示，保存在本机，随时可以恢复。")
                }
                Section {
                    Button {
                        dismiss()
                        AppNavigationCenter.shared.open(.financeRecords)
                    } label: {
                        Label("打开数据管理", systemImage: "externaldrive")
                            .frame(minHeight: 44)
                    }
                    Text("在记账页右上角的「…」菜单中，可导出全量 JSON 备份、恢复备份或导入账单。")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("备份与迁移")
                }
                Section("关于 LifeOS") {
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    LabeledContent("数据存储", value: "本机 SwiftData")
                    Text("情报官简报由本地规则生成。当前没有接入云端 AI，收支、学习与日程记录不会通过本功能上传。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .tint(ArchiveTheme.mintDeep)
            .navigationTitle("偏好与数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                importing = true
                Task { @MainActor in
                    defer { photoItem = nil; importing = false }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            artworkError = "这张图片无法读取，请换一张后重试。"
                            return
                        }
                        try artwork.importImage(data: data)
                    } catch {
                        artworkError = "导入失败：\(error.localizedDescription)"
                    }
                }
            }
            .alert("无法导入立绘", isPresented: Binding(
                get: { artworkError != nil },
                set: { if !$0 { artworkError = nil } }
            )) {
                Button("好") { artworkError = nil }
            } message: {
                Text(artworkError ?? "")
            }
        }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
    }
}
