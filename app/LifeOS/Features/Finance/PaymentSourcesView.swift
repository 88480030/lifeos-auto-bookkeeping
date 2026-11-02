import SwiftUI

/// Provider labels and imported files are local record provenance, not account connections.
struct PaymentSourcesView: View {
    let transactions: [MoneyTransaction]
    let onImportStatement: () -> Void
    var onRecognizeScreenshot: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("账目从哪里来")
                            .font(.title2.weight(.bold))
                        Text("微信和支付宝均未绑定账户。当前账目来自手动记账、你导入的账单文件，或你确认保存的截图识别结果。")
                            .font(.body)
                            .foregroundStyle(ArchiveTheme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 20) {
                        providerRow(name: "微信支付", prefix: "wechat:", channel: .wechat, symbol: "message")
                        Divider().overlay(ArchiveTheme.rule)
                        providerRow(name: "支付宝", prefix: "alipay:", channel: .alipay, symbol: "a.circle")
                    }
                    .padding(18)
                    .background(ArchiveTheme.paperRaised, in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 12) {
                        Label("账单导入可用", systemImage: "doc.text")
                            .font(.headline)
                        Text("从微信或支付宝导出 CSV 账单，保存到「文件」后在此选择。导入前可以预览；已导入的交易按交易号或指纹去重。")
                            .font(.subheadline)
                            .foregroundStyle(ArchiveTheme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            Haptics.tap()
                            onImportStatement()
                        } label: {
                            Label("选择账单文件", systemImage: "tray.and.arrow.down")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .padding(.horizontal, 12)
                                .foregroundStyle(ArchiveTheme.paper)
                                .background(ArchiveTheme.ink, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(PressableScaleStyle())
                        .accessibilityIdentifier("finance.importStatementFromSources")
                    }

                    if let onRecognizeScreenshot {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("付款截图记账", systemImage: "doc.text.viewfinder")
                                .font(.headline)
                            Text("选一张付款详情截图，在本机识别金额、商家和日期，核对分类后保存。截图识别是辅助录入，不会连接支付账户。")
                                .font(.subheadline)
                                .foregroundStyle(ArchiveTheme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(action: onRecognizeScreenshot) {
                                Label("从截图记一笔", systemImage: "photo")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .foregroundStyle(ArchiveTheme.ink)
                                    .background(ArchiveTheme.mintWash, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(DepthPressStyle())
                            .accessibilityIdentifier("finance.captureReceiptFromSources")
                        }
                    }

                    Label {
                        Text("选择「微信」或「支付宝」支付方式只会添加标签。导入账单后也不会自动同步新消费。")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(ArchiveTheme.inkSoft)
                }
                .padding(AppTheme.pagePadding)
                .padding(.bottom, 20)
            }
            .background(ArchiveTheme.paper)
            .foregroundStyle(ArchiveTheme.ink)
            .navigationTitle("账单来源说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(ArchiveTheme.ink)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("关闭账单来源说明")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func providerRow(name: String, prefix: String, channel: PaymentChannel, symbol: String) -> some View {
        let importedCount = transactions.filter { $0.externalID?.hasPrefix(prefix) == true }.count
        let manualCount = transactions.filter { $0.channel == channel && $0.externalID == nil }.count
        let receiptCount = transactions.filter {
            $0.externalID?.hasPrefix("receipt:" + channel.rawValue + ":") == true
                || ($0.externalID?.hasPrefix("receipt:sha256:") == true && $0.channel == channel)
        }.count
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))

        return layout {
            Image(systemName: symbol)
                .font(.title2.weight(.medium))
                .frame(width: 44, height: 44)
                .background(ArchiveTheme.mintWash, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.headline)
                Text("账户未绑定 · 无自动同步")
                    .font(.subheadline.weight(.medium))
                Text("账单导入 \(importedCount) 笔 · 截图确认 \(receiptCount) 笔 · 手动标记 \(manualCount) 笔")
                    .font(.caption)
                    .foregroundStyle(ArchiveTheme.inkSoft)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
