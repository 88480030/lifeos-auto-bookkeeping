import SwiftUI

/// 每日人民币支出与角色档位。角色预览与实际支出明确分开，不会修改账单。
struct DailySpendingPanel: View {
    let transactions: [MoneyTransaction]
    let date: Date
    var currencyCode: String = "CNY"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var previewTier: DailySpendingTier?
    @State private var responseRevision = 0

    private var totals: FinanceTotals {
        FinanceAnalytics.totals(transactions, on: date, currencyCode: currencyCode)
    }

    private var actualTier: DailySpendingTier? {
        DailySpendingTier.matching(expenseMinor: totals.expenseMinor, currencyCode: currencyCode)
    }

    private var displayedTier: DailySpendingTier { previewTier ?? actualTier ?? .twenty }
    private var isCNY: Bool { currencyCode.uppercased() == "CNY" }
    private var isOver: Bool {
        DailySpendingTier.isAboveHighestTier(expenseMinor: totals.expenseMinor, currencyCode: currencyCode)
    }

    var body: some View {
        let motionEnabled = !reduceMotion
        MangaPanel(fill: ArchiveTheme.paperRaised, borderWidth: 1.4, hardShadow: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Calendar.current.isDateInToday(date) ? "今日消费" : "当日消费")
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(date, format: .dateTime.month().day())
                        .font(.caption)
                        .foregroundStyle(ArchiveTheme.inkSoft)
                }

                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 18))
                layout {
                    Button {
                        Haptics.select()
                        responseRevision += 1
                    } label: {
                        DailySpendingAvatar(tier: displayedTier, size: 94, animates: true, reactionRevision: responseRevision)
                            .keyframeAnimator(initialValue: CGFloat(1), trigger: responseRevision) { content, scale in
                                content.scaleEffect(motionEnabled ? scale : 1)
                            } keyframes: { _ in
                                CubicKeyframe(1.07, duration: 0.12)
                                CubicKeyframe(1, duration: 0.3)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if reduceMotion && responseRevision > 0 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(ArchiveTheme.ink)
                                        .background(ArchiveTheme.paperRaised, in: Circle())
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                    .buttonStyle(SpendingAvatarPressStyle())
                    .accessibilityLabel("\(displayedTier.characterName)动态头像")
                    .accessibilityHint("轻点让角色回应")
                    .accessibilityValue(responseRevision > 0 ? "角色已回应" : "轻点互动")

                    VStack(alignment: .leading, spacing: 6) {
                        Text(MoneyFormatter.string(minorUnits: totals.expenseMinor, currencyCode: currencyCode))
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.numericText())
                        Text(statusText)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(previewTier == nil ? displayedTier.characterName + "陪你看账单" : "角色预览 · " + displayedTier.characterName)
                            .font(.caption)
                            .foregroundStyle(ArchiveTheme.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isCNY {
                    Divider().overlay(ArchiveTheme.rule)
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(DailySpendingTier.allCases) { tier in
                                tierButton(tier)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)

                    if previewTier != nil {
                        Button {
                            Haptics.select()
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { previewTier = nil }
                        } label: {
                            Label("回到实际消费", systemImage: "arrow.uturn.backward")
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("spending.resetPreview")
                    }

                    Text("按实际人民币支出自动分档；点头像可预览。超过 ¥100 保留第五档，并显示超出金额。")
                        .font(.caption)
                        .foregroundStyle(ArchiveTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("五档头像仅用于人民币；\(currencyCode.uppercased()) 按原币种展示，不作换算。")
                        .font(.caption)
                        .foregroundStyle(ArchiveTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Haptics.select()
                    AppNavigationCenter.shared.open(.financeRecords, scheduleDate: date)
                } label: {
                    HStack(spacing: 8) {
                        Label("查看账目", systemImage: "list.bullet.rectangle")
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SpendingAvatarPressStyle())
                .accessibilityHint("查看该日的实际收支记录")
                .accessibilityIdentifier("spending.openRecords")

                Button {
                    Haptics.select()
                    ReceiptCaptureCenter.shared.present()
                } label: {
                    Label("从付款截图记一笔", systemImage: "doc.text.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SpendingAvatarPressStyle())
                .accessibilityHint("选择截图，本机识别后核对保存")
                .accessibilityIdentifier("spending.captureReceipt")
            }
            .foregroundStyle(ArchiveTheme.ink)
        }
        .accessibilityIdentifier("spending.dailyPanel")
        .onChange(of: Calendar.current.startOfDay(for: date)) { _, _ in previewTier = nil }
        .onChange(of: currencyCode) { _, _ in previewTier = nil }
    }

    private var statusText: String {
        if !isCNY { return "\(currencyCode.uppercased()) 实际支出" }
        if previewTier != nil { return displayedTier.rangeText + "档头像" }
        if totals.expenseMinor == 0 {
            return Calendar.current.isDateInToday(date) ? "今天还没有人民币支出" : "当天还没有人民币支出"
        }
        if isOver {
            return "超过 ¥100 · 多出 " + MoneyFormatter.string(minorUnits: totals.expenseMinor - DailySpendingTier.hundred.rawValue, currencyCode: "CNY")
        }
        return displayedTier.rangeText + "档 · 实际支出"
    }

    private func tierButton(_ tier: DailySpendingTier) -> some View {
        let selected = displayedTier == tier && (previewTier != nil || actualTier != nil)
        return Button {
            Haptics.select()
            withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.8)) {
                previewTier = tier
            }
            responseRevision += 1
        } label: {
            VStack(spacing: 5) {
                DailySpendingAvatar(tier: tier, size: 42, animates: false)
                Text("¥\(tier.upperBoundYuan)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                if selected {
                    Image(systemName: previewTier == nil ? "checkmark.circle.fill" : "eye.fill")
                        .font(.caption2)
                } else {
                    Color.clear.frame(height: 11)
                }
            }
            .foregroundStyle(ArchiveTheme.ink)
            .frame(minWidth: 50, minHeight: 76)
            .padding(.horizontal, 3)
            .padding(.vertical, 6)
            .background(selected ? tier.wash : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(SpendingAvatarPressStyle())
        .accessibilityLabel("\(tier.rangeText)档，\(tier.characterName)")
        .accessibilityHint("预览该档动态头像，不修改记录")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("spending.tier.\(tier.upperBoundYuan)")
    }
}

/// 仅头像区域使用本地动画时钟；金额与账单查询不会随帧重算。
struct DailySpendingAvatar: View {
    let tier: DailySpendingTier
    let size: CGFloat
    var animates = false
    var reactionRevision = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.lifeOSSurfaceVisible) private var surfaceVisible
    @State private var mounted = false
    @State private var inViewport = true
    @State private var reactionStartedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
            let phase = isAnimating ? timeline.date.timeIntervalSinceReferenceDate * 1.7 : 0
            ZStack {
                Circle().fill(tier.wash)
                Image(frameAssetName(at: timeline.date))
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.96, height: size * 0.96)
                    .offset(y: isAnimating ? sin(phase) * size * 0.016 : 0)
                    .scaleEffect(reactionScale(at: timeline.date))
                    .rotation3DEffect(.degrees(isAnimating ? sin(phase * 0.7) * 3 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                    .transaction { $0.animation = nil }
            }
            .frame(width: size, height: size)
            .shadow(color: ArchiveTheme.shadow.opacity(0.12), radius: 4, x: 0, y: 3)
        }
        .onAppear { mounted = true }
        .onDisappear { mounted = false }
        .onChange(of: reactionRevision) { _, _ in
            reactionStartedAt = reduceMotion ? nil : .now
        }
        .onChange(of: tier) { _, _ in
            reactionStartedAt = reduceMotion ? nil : .now
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { reactionStartedAt = nil }
        }
        .modifier(CompanionViewportObserver(isVisible: $inViewport))
        .accessibilityHidden(true)
    }

    private var isAnimating: Bool {
        animates && mounted && inViewport && surfaceVisible && !reduceMotion && scenePhase == .active
    }

    private func reactionScale(at date: Date) -> CGFloat {
        guard isAnimating, let start = reactionStartedAt else { return 1 }
        let elapsed = date.timeIntervalSince(start)
        guard elapsed >= 0, elapsed < 0.6 else { return 1 }
        return 1 + CGFloat(sin(elapsed / 0.6 * .pi)) * 0.055
    }

    /// Keep the same image throughout the animation to avoid flashing.
    private func frameAssetName(at date: Date) -> String { tier.assetName }

}

private struct SpendingAvatarPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .rotation3DEffect(.degrees(configuration.isPressed && !reduceMotion ? 8 : 0), axis: (x: 1, y: -0.6, z: 0), perspective: 0.5)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension DailySpendingTier {
    var characterName: String {
        switch self {
        case .twenty: "小水獭"
        case .thirty: "小熊"
        case .forty: "小兔"
        case .fifty: "小猫"
        case .hundred: "小狐狸"
        }
    }

    var assetName: String {
        switch self {
        case .twenty: "MascotOtter"
        case .thirty: "MascotBear"
        case .forty: "MascotRabbit"
        case .fifty: "MascotCat"
        case .hundred: "MascotFox"
        }
    }

    var rangeText: String {
        switch self {
        case .twenty: "¥20 以内"
        case .thirty: "¥20–30"
        case .forty: "¥30–40"
        case .fifty: "¥40–50"
        case .hundred: "¥50–100"
        }
    }

    var wash: Color {
        switch self {
        case .twenty: ArchiveTheme.pinkWash
        case .thirty: ArchiveTheme.paperTint
        case .forty: ArchiveTheme.goldWash
        case .fifty: ArchiveTheme.sageWash
        case .hundred: ArchiveTheme.mintWash
        }
    }
}
