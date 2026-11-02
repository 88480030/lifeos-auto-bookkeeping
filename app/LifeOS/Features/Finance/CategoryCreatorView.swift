import SwiftUI

struct CategoryCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CustomCategoryStore
    var onCreated: (CustomCategory) -> Void

    @State private var name = ""
    @State private var symbol = CategoryCatalog.symbolChoices.first ?? "tag.fill"
    @State private var colorHex = CategoryCatalog.paletteHexes.first ?? 0x9C752F
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(AppTheme.surface.opacity(0.7)))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("新建分类")
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Color.clear.frame(width: 34, height: 34)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: "Name")
                            TextField("例如：宠物、旅行、人情", text: $name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "图标", eyebrow: "Symbol")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                            ForEach(CategoryCatalog.symbolChoices, id: \.self) { item in
                                Button {
                                    Haptics.tap()
                                    symbol = item
                                } label: {
                                    Image(systemName: item)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(symbol == item ? AppTheme.textPrimary : AppTheme.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 42)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(symbol == item ? Color(hex: colorHex).opacity(0.20) : AppTheme.surface.opacity(0.4))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(symbol == item ? Color(hex: colorHex) : AppTheme.separator.opacity(0.6), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "颜色", eyebrow: "Color")
                        HStack(spacing: 10) {
                            ForEach(CategoryCatalog.paletteHexes, id: \.self) { hex in
                                Button {
                                    Haptics.tap()
                                    colorHex = hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white.opacity(colorHex == hex ? 0.9 : 0), lineWidth: 2)
                                        )
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color(hex: hex).opacity(colorHex == hex ? 0.6 : 0), lineWidth: 3)
                                                .padding(-3)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.coral)
                    }

                    Button {
                        save()
                    } label: {
                        Text("创建分类")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x1A1206))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [AppTheme.goldBright, AppTheme.gold],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    }
                    .buttonStyle(PressableScaleStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .background {
            AppBackground()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard store.add(name: trimmed, symbol: symbol, colorHex: colorHex) else {
            errorMessage = "分类已存在，或与内置分类重名。"
            return
        }
        onCreated(CustomCategory(name: trimmed, symbol: symbol, colorHex: colorHex))
        Haptics.success()
        dismiss()
    }
}
