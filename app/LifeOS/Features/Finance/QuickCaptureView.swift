import Foundation
import SwiftUI
import SwiftData

struct QuickCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let request: QuickCaptureRequest
    let onClose: (() -> Void)?

    init(request: QuickCaptureRequest, onClose: (() -> Void)? = nil) {
        self.request = request
        self.onClose = onClose
    }

    @StateObject private var categoryStore = CustomCategoryStore()

    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var note = ""
    @State private var selectedCategory = BuiltInCategory.dining.rawValue
    @State private var channel: PaymentChannel = .wechat
    @State private var currencyCode = "CNY"
    @State private var didLoadDefaults = false
    @State private var saved = false
    @State private var saveError: String?

    @FocusState private var noteFocused: Bool

    private let defaults = UserDefaults.standard
    private let kindKey = "lifeos.quickCapture.kind"
    private let categoryKey = "lifeos.quickCapture.category"
    private let channelKey = "lifeos.quickCapture.channel"
    private let currencyKey = "lifeos.quickCapture.currency"

    private var parsedMinorUnits: Int? {
        MoneyParser.minorUnits(from: amountText, currencyCode: currencyCode)
    }

    private var canSave: Bool {
        guard let parsedMinorUnits else { return false }
        return parsedMinorUnits > 0
    }

    private var categoryOptions: [CategoryOption] {
        kind == .expense
            ? CategoryCatalog.expenseOptions(custom: categoryStore.categories)
            : CategoryCatalog.incomeOptions(custom: categoryStore.categories)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)

            amountCard
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 10)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    kindAndCurrencyRow
                    categorySection
                    channelSection
                    noteRow
                    quickAmountsSection

                    if dynamicTypeSize.isAccessibilitySize && !noteFocused {
                        keypad
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.top)
            .clipped()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if !dynamicTypeSize.isAccessibilitySize && !noteFocused {
                    keypad
                        .padding(.horizontal, AppTheme.pagePadding)
                }
                saveBar
            }
            .background { AppBackground() }
        }
        .background { AppBackground() }
        .onAppear(perform: loadDefaultsIfNeeded)
        .overlay {
            if saved {
                savedToast
            }
        }
        .alert("记账未能保存", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("继续编辑", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "填写内容已保留，请重试。")
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppTheme.surface.opacity(0.7)))
                    .overlay(Circle().strokeBorder(AppTheme.separator.opacity(0.7), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭一键记账")

            Spacer()

            VStack(spacing: 2) {
                Text("一键记账")
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("QUICK CAPTURE")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(AppTheme.gold)
                }
            }

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Amount

    private var amountCard: some View {
        SurfaceCard(padding: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(CurrencyCatalog.symbol(for: currencyCode))
                    .font(.title2.weight(.medium))
                    .foregroundStyle(AppTheme.gold)

                Text(amountText.isEmpty ? "0.00" : amountText)
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(amountText.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("记账金额")
        .accessibilityValue("\(currencyCode) \(amountText.isEmpty ? "0.00" : amountText)")
    }

    private var kindAndCurrencyRow: some View {
        kindAndCurrencyLayout {
            HStack(spacing: 2) {
                ForEach(TransactionKind.allCases, id: \.self) { item in
                    Button {
                        guard kind != item else { return }
                        Haptics.select()
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            kind = item
                            selectedCategory = item == .expense
                                ? BuiltInCategory.dining.rawValue
                                : (CategoryCatalog.incomeCategories.first?.id ?? "其他收入")
                        }
                    } label: {
                        Text(item.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                kind == item
                                    ? (item == .expense ? AppTheme.coral : AppTheme.accent)
                                    : AppTheme.textTertiary
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .frame(minWidth: 44, minHeight: 44)
                            .background {
                                if kind == item {
                                    Capsule(style: .continuous)
                                        .fill((item == .expense ? AppTheme.coral : AppTheme.accent).opacity(0.12))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(kind == item ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Capsule(style: .continuous).fill(AppTheme.surface.opacity(0.45)))
            .overlay(Capsule(style: .continuous).strokeBorder(AppTheme.separator.opacity(0.7), lineWidth: 0.8))

            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }

            Menu {
                ForEach(CurrencyCatalog.supportedCurrencyCodes, id: \.self) { code in
                    Button {
                        Haptics.select()
                        currencyCode = code
                    } label: {
                        Text("\(code) · \(CurrencyCatalog.displayName(for: code))")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currencyCode)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 44, minHeight: 44)
                .background(Capsule(style: .continuous).fill(AppTheme.surface.opacity(0.55)))
                .overlay(Capsule(style: .continuous).strokeBorder(AppTheme.separator.opacity(0.75), lineWidth: 0.8))
            }
            .accessibilityLabel("选择币种，当前 \(currencyCode)")
        }
    }

    private var kindAndCurrencyLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
    }

    // MARK: - Categories / channel

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Category")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categoryOptions.prefix(12)) { option in
                        categoryChip(option)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func categoryChip(_ option: CategoryOption) -> some View {
        let isSelected = option.id == selectedCategory

        return Button {
            Haptics.tap()
            selectedCategory = option.id
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option.symbol)
                    .font(.subheadline.weight(.medium))
                Text(option.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? option.color : AppTheme.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? option.color.opacity(0.14) : AppTheme.surface.opacity(0.45))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? option.color.opacity(0.5) : AppTheme.separator.opacity(0.65), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Channel")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PaymentChannel.allCases, id: \.self) { item in
                        channelChip(item)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func channelChip(_ item: PaymentChannel) -> some View {
        let isSelected = channel == item
        return Button {
            Haptics.tap()
            channel = item
        } label: {
            HStack(spacing: 5) {
                Image(systemName: item.symbolName)
                    .font(.subheadline.weight(.medium))
                Text(item.displayName)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(isSelected ? AppTheme.gold : AppTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: 44, minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AppTheme.gold.opacity(0.10) : AppTheme.surface.opacity(0.40))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.gold.opacity(0.45) : AppTheme.separator.opacity(0.6), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var noteRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "text.alignleft")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.gold)
            TextField("备注（可选）", text: $note)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .focused($noteFocused)
                .submitLabel(.done)
                .onSubmit { noteFocused = false }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.separator.opacity(0.7), lineWidth: 0.8)
        )
    }

    private var quickAmountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Quick Amounts")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(quickAmountValues, id: \.self) { value in
                        Button {
                            Haptics.tap()
                            amountText = "\(value)"
                        } label: {
                            Text("\(value)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(AppTheme.surface.opacity(0.45))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(AppTheme.separator.opacity(0.65), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(PressableScaleStyle())
                    }
                }
            }
        }
    }

    private var quickAmountValues: [Int] {
        currencyCode == "JPY" ? [500, 1000, 2000, 5000] : [10, 20, 30, 50, 100]
    }

    // MARK: - Keypad

    private var keypad: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"], id: \.self) { key in
                keyButton(key)
            }
        }
        .padding(.top, 4)
    }

    private func keyButton(_ key: String) -> some View {
        Button {
            pressKey(key)
        } label: {
            Text(key)
                .font(.title2.weight(.medium))
                .foregroundStyle(key == "⌫" ? AppTheme.textSecondary : AppTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .frame(minHeight: 46)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.surface.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppTheme.separator.opacity(0.6), lineWidth: 0.8)
                )
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel(key == "⌫" ? "删除" : key)
    }

    private func pressKey(_ key: String) {
        Haptics.tap()
        switch key {
        case "⌫":
            if !amountText.isEmpty {
                amountText.removeLast()
            }
        case ".":
            guard CurrencyCatalog.minorUnitDigits(for: currencyCode) > 0 else { return }
            guard !amountText.contains(".") else { return }
            amountText = amountText.isEmpty ? "0." : amountText + "."
        default:
            if amountText == "0" {
                amountText = key
            } else {
                amountText += key
            }

            let digits = CurrencyCatalog.minorUnitDigits(for: currencyCode)
            if let dot = amountText.firstIndex(of: ".") {
                let fractionCount = amountText.distance(from: amountText.index(after: dot), to: amountText.endIndex)
                if fractionCount > digits {
                    amountText.removeLast()
                }
            }
        }
    }

    // MARK: - Save

    private var saveBar: some View {
        Button {
            save()
        } label: {
            HStack {
                Text("保存")
                    .font(.body.weight(.semibold))
                Spacer()
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(Color(hex: 0x1A1206))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(minHeight: 50)
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
        .disabled(!canSave || saved)
        .opacity(canSave ? 1 : 0.45)
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var savedToast: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.gold)
            Text("已记账")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surface.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AppTheme.gold.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Logic

    private func loadDefaultsIfNeeded() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true

        if let raw = defaults.string(forKey: kindKey), let storedKind = TransactionKind(rawValue: raw) {
            kind = storedKind
        }
        if let raw = defaults.string(forKey: currencyKey), !raw.isEmpty {
            currencyCode = raw
        }
        if let raw = defaults.string(forKey: categoryKey), !raw.isEmpty {
            selectedCategory = raw
        } else {
            selectedCategory = kind == .expense
                ? BuiltInCategory.dining.rawValue
                : (CategoryCatalog.incomeCategories.first?.id ?? "其他收入")
        }
        if let raw = defaults.string(forKey: channelKey), let storedChannel = PaymentChannel(rawValue: raw) {
            channel = storedChannel
        }

        if let categoryName = request.categoryName,
           let option = categoryOptions.first(where: { $0.name == categoryName || $0.id == categoryName }) {
            selectedCategory = option.id
        }

        if let requestAmount = request.amount {
            amountText = Self.inputString(amount: requestAmount, currencyCode: currencyCode)
        }

        if let requestNote = request.note {
            note = requestNote
        }
    }

    private func save() {
        guard !saved, let minor = parsedMinorUnits, minor > 0 else { return }

        let transaction = MoneyTransaction(
            amountMinor: minor,
            currencyCode: currencyCode,
            kind: kind,
            categoryRaw: selectedCategory,
            channel: channel,
            occurredAt: .now,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            merchant: ""
        )
        context.insert(transaction)
        do {
            try context.save()
        } catch {
            // This record has not been persisted. Remove only this insertion so
            // a retry creates one record without rolling back unrelated edits.
            context.delete(transaction)
            saveError = "这笔记录尚未保存。填写内容已保留，请重试。"
            return
        }

        defaults.set(kind.rawValue, forKey: kindKey)
        defaults.set(selectedCategory, forKey: categoryKey)
        defaults.set(channel.rawValue, forKey: channelKey)
        defaults.set(currencyCode, forKey: currencyKey)

        Haptics.success()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            saved = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            close()
        }
    }

    private static func inputString(amount: Double, currencyCode: String) -> String {
        let digits = CurrencyCatalog.minorUnitDigits(for: currencyCode)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: amount)) ?? String(amount)
    }
}
