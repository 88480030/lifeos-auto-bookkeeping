import SwiftUI

struct StatementPreviewItem: Identifiable {
    let id = UUID()
    let result: StatementParseResult
}

struct StatementImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let result: StatementParseResult
    let existingExternalIDs: Set<String>
    var existingTransactions: [MoneyTransaction] = []
    let onImport: ([ImportedTransaction]) -> Void

    private var newTransactions: [ImportedTransaction] {
        result.transactions.filter { !isDuplicate($0) }
    }

    private func isDuplicate(_ transaction: ImportedTransaction) -> Bool {
        existingExternalIDs.contains(transaction.externalID)
            || ReceiptDuplicateMatcher.isExactImportDuplicate(transaction, existing: existingTransactions)
    }

    private var duplicateCount: Int {
        result.transactions.count - newTransactions.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    if !result.warnings.isEmpty {
                        warningsCard
                    }
                    listSection
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            importBar
        }
        .background {
            AppBackground()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AppTheme.surface.opacity(0.7)))
                    .overlay(Circle().strokeBorder(AppTheme.separator.opacity(0.7), lineWidth: 0.8))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("导入预览")
                .font(.system(.headline, design: .serif).weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var summaryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    PillBadge(text: result.source.displayName, tint: AppTheme.gold)
                    Spacer()
                    Text(result.fileName)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 18) {
                    summaryColumn("有效", "\(result.transactions.count)", tint: AppTheme.accent)
                    summaryColumn("可导入", "\(newTransactions.count)", tint: AppTheme.gold)
                    summaryColumn("重复", "\(duplicateCount)", tint: AppTheme.textSecondary)
                    summaryColumn("原始行", "\(result.totalRows)", tint: AppTheme.textTertiary)
                }

                Text("只会导入未重复的记录；重复项按交易单号 / 指纹识别。")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private func summaryColumn(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Eyebrow(text: title, tint: tint)
            Text(value)
                .font(.system(size: 18, weight: .semibold).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private var warningsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Eyebrow(text: "Warnings", tint: AppTheme.coral)
                    Spacer()
                    Text("\(result.warnings.count) 条")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                ForEach(result.warnings, id: \.self) { warning in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(AppTheme.coral.opacity(0.7))
                            .frame(width: 4, height: 4)
                            .padding(.top, 5)
                        Text(warning)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "解析结果",
                eyebrow: "Preview",
                trailing: "\(result.transactions.count) 笔"
            )

            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(result.transactions.enumerated()), id: \.element.id) { index, transaction in
                        previewRow(transaction)
                        if index < result.transactions.count - 1 {
                            Rectangle()
                                .fill(AppTheme.separator.opacity(0.55))
                                .frame(height: 0.7)
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private func previewRow(_ transaction: ImportedTransaction) -> some View {
        let isDuplicate = isDuplicate(transaction)
        let option = CategoryCatalog.option(
            for: transaction.categoryRaw,
            kind: transaction.kind,
            custom: []
        )

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(option.color.opacity(0.13))
                    .frame(width: 34, height: 34)
                Image(systemName: option.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(option.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(transaction.merchant.isEmpty ? option.name : transaction.merchant)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    if transaction.isRefund {
                        PillBadge(text: "退款", tint: AppTheme.accent)
                    }
                    if transaction.isTransfer {
                        PillBadge(text: "转账", tint: AppTheme.indigo)
                    }
                    if isDuplicate {
                        PillBadge(text: "重复", tint: AppTheme.textTertiary)
                    }
                }

                Text("\(AppFormatters.dateTime(transaction.occurredAt)) · \(option.name)")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(signedAmount(transaction))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(FinanceFormatting.amountColor(for: transaction.kind))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .opacity(isDuplicate ? 0.45 : 1)
    }

    private func signedAmount(_ transaction: ImportedTransaction) -> String {
        let absolute = MoneyFormatter.string(
            minorUnits: abs(transaction.amountMinor),
            currencyCode: transaction.currencyCode
        )
        return transaction.kind == .expense ? "-\(absolute)" : "+\(absolute)"
    }

    private var importBar: some View {
        VStack(spacing: 8) {
            Button {
                onImport(newTransactions)
                dismiss()
            } label: {
                HStack {
                    Text("导入 \(newTransactions.count) 笔记录")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color(hex: 0x1A1206))
                .padding(.horizontal, 20)
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
            .disabled(newTransactions.isEmpty)
            .opacity(newTransactions.isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            (colorScheme == .dark ? Color(hex: 0x070A09) : Color(hex: 0xF3EFE5))
                .opacity(0.97)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
