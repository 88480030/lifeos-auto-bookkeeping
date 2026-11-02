import SwiftUI
import SwiftData

struct BudgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let month: Date
    let currencyCode: String
    let existingBudget: Budget?

    @State private var amountText: String
    @State private var showingDeleteConfirmation = false
    @State private var operationError: String?

    init(month: Date, currencyCode: String, existingBudget: Budget?) {
        self.month = month
        self.currencyCode = currencyCode
        self.existingBudget = existingBudget
        _amountText = State(
            initialValue: existingBudget.map {
                Self.inputString(minorUnits: $0.amountMinor, currencyCode: $0.currencyCode)
            } ?? ""
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(AppTheme.surface.opacity(0.7)))
                        .overlay(Circle().strokeBorder(AppTheme.separator.opacity(0.7), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭预算编辑")

                Spacer()

                Text("\(AppFormatters.monthTitle(month))预算")
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Eyebrow(text: "Monthly Budget")
                                Spacer()
                                Text(currencyCode)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }

                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(CurrencyCatalog.symbol(for: currencyCode))
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundStyle(AppTheme.gold)
                                TextField("0.00", text: $amountText)
                                    .font(.system(size: 40, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .keyboardType(.decimalPad)
                            }

                            if let validationMessage {
                                Text(validationMessage)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.coral)
                            }
                        }
                    }

                    Text("预算按月份和币种分别保存，不会与日元等其他币种混算。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)

                    if existingBudget != nil {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("删除本月预算", systemImage: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.coral)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Capsule(style: .continuous).fill(AppTheme.coral.opacity(0.08)))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(AppTheme.coral.opacity(0.25), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(PressableScaleStyle())
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)

            Button {
                save()
            } label: {
                Text("保存预算")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1A1206))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
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
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .background {
            AppBackground()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("删除本月预算？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteBudget() }
        } message: {
            Text("仅删除 \(AppFormatters.monthTitle(month)) 的 \(currencyCode) 预算，收支记录会保留。")
        }
        .alert("操作未完成", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("好") { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    private var parsedMinorUnits: Int? {
        MoneyParser.minorUnits(from: amountText, currencyCode: currencyCode)
    }

    private var canSave: Bool {
        guard let parsedMinorUnits else { return false }
        return parsedMinorUnits > 0
    }

    private var validationMessage: String? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parsedMinorUnits else { return "金额格式不正确" }
        return parsedMinorUnits > 0 ? nil : "预算需要大于 0"
    }

    private func save() {
        guard let minor = parsedMinorUnits, minor > 0 else { return }

        if let existingBudget {
            existingBudget.amountMinor = minor
        } else {
            let budget = Budget(
                monthKey: DayKey.monthKey(for: month),
                amountMinor: minor,
                currencyCode: currencyCode
            )
            context.insert(budget)
        }

        do {
            try context.save()
            Haptics.success()
            dismiss()
        } catch {
            context.rollback()
            operationError = "预算未能保存，填写的金额仍在。请重试。\n\(error.localizedDescription)"
        }
    }

    private func deleteBudget() {
        guard let existingBudget else { return }
        context.delete(existingBudget)
        do {
            try context.save()
            Haptics.success()
            dismiss()
        } catch {
            context.rollback()
            operationError = "删除失败，预算已保留。请重试。\n\(error.localizedDescription)"
        }
    }

    private static func inputString(minorUnits: Int, currencyCode: String) -> String {
        let digits = CurrencyCatalog.minorUnitDigits(for: currencyCode)
        let absolute = abs(minorUnits)
        var divisor = 1
        for _ in 0..<digits {
            divisor *= 10
        }
        let whole = absolute / divisor
        let fraction = absolute % divisor
        if digits == 0 {
            return "\(whole)"
        }
        return "\(whole)." + String(format: "%0\(digits)d", fraction)
    }
}
