import SwiftUI
import SwiftData

struct TransactionEditorView: View {
    private enum Field: Hashable {
        case amount
        case note
        case merchant
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize: CGFloat = 44

    private let editingTransaction: MoneyTransaction?
    private let defaultCurrencyCode: String
    private let receiptDraft: ReceiptEditorDraft?
    @ObservedObject private var categoryStore: CustomCategoryStore
    @Query(sort: \MoneyTransaction.occurredAt, order: .reverse)
    private var existingTransactions: [MoneyTransaction]

    @State private var kind: TransactionKind
    @State private var amountText: String
    @State private var currencyCode: String
    @State private var categoryRaw: String
    @State private var channel: PaymentChannel
    @State private var occurredAt: Date
    @State private var note: String
    @State private var merchant: String
    @State private var showingCategoryCreator = false
    @State private var showingDeleteConfirmation = false
    @State private var operationError: String?
    @State private var showingPossibleReceiptDuplicate = false
    @State private var receiptDuplicateMessage = ""
    @State private var didSave = false
    @State private var receiptTimeWasEdited = false

    @FocusState private var focusedField: Field?

    init(transaction: MoneyTransaction?, defaultCurrencyCode: String, categoryStore: CustomCategoryStore, receiptDraft: ReceiptEditorDraft? = nil) {
        self.editingTransaction = transaction
        self.defaultCurrencyCode = defaultCurrencyCode
        self.receiptDraft = transaction == nil ? receiptDraft : nil
        _categoryStore = ObservedObject(wrappedValue: categoryStore)

        let seed = transaction == nil ? receiptDraft : nil
        let seedKind = seed?.result.kind ?? .expense
        let seedCurrency = seed?.selectedAmount?.currencyCode ?? defaultCurrencyCode
        _kind = State(initialValue: transaction?.kind ?? seedKind)
        _currencyCode = State(initialValue: transaction?.currencyCode ?? seedCurrency)
        _amountText = State(
            initialValue: transaction.map {
                Self.amountString(minorUnits: $0.amountMinor, currencyCode: $0.currencyCode)
            } ?? seed?.selectedAmount.map {
                Self.amountString(minorUnits: $0.amountMinor, currencyCode: $0.currencyCode)
            } ?? ""
        )
        let seedCategory = seedKind == .income ? "其他收入" : (seed?.result.categoryRaw ?? BuiltInCategory.dining.rawValue)
        _categoryRaw = State(initialValue: transaction?.categoryRaw ?? seedCategory)
        _channel = State(initialValue: transaction?.channel ?? seed?.result.channel ?? (seed == nil ? .wechat : .other))
        _occurredAt = State(initialValue: transaction?.occurredAt ?? seed?.result.occurredAt ?? .now)
        #if DEBUG
        let fixtureNote = seed != nil && ProcessInfo.processInfo.arguments.contains("-receiptFixture") ? "[QA] 截图识别测试样张" : ""
        #else
        let fixtureNote = ""
        #endif
        _note = State(initialValue: transaction?.note ?? fixtureNote)
        _merchant = State(initialValue: transaction?.merchant ?? seed?.result.merchant ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if receiptDraft != nil { receiptReviewNotice }
                    amountCard
                    categorySection
                    channelSection
                    detailsCard

                    if editingTransaction != nil {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("删除这笔记录", systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.coral)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(AppTheme.coral.opacity(0.08))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(AppTheme.coral.opacity(0.25), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(PressableScaleStyle())
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            saveBar
        }
        .background {
            AppBackground()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingCategoryCreator) {
            CategoryCreatorView(store: categoryStore) { created in
                categoryRaw = created.name
            }
        }
        .confirmationDialog("删除记录？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteTransaction() }
        } message: {
            Text("删除后无法恢复。")
        }
        .confirmationDialog("可能是重复账目", isPresented: $showingPossibleReceiptDuplicate, titleVisibility: .visible) {
            Button("仍然保存一笔") { persist(allowPossibleDuplicate: true) }
            Button("返回核对", role: .cancel) {}
        } message: {
            Text(receiptDuplicateMessage)
        }
        .alert("操作未完成", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("好") { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
            }
        }
        .onChange(of: kind) { _, newKind in
            adjustCategory(for: newKind)
        }
        .onChange(of: occurredAt) { previous, current in
            let calendar = Calendar.current
            if calendar.dateComponents([.hour, .minute], from: previous)
                != calendar.dateComponents([.hour, .minute], from: current) {
                receiptTimeWasEdited = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
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
            .accessibilityLabel("关闭记录编辑")

            Spacer()

            Text(receiptDraft != nil ? "核对截图记账" : editingTransaction == nil ? "记一笔" : "编辑记录")
                .font(.system(.headline, design: .serif).weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Amount

    private var receiptReviewNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("请核对后保存", systemImage: "doc.text.viewfinder")
                .font(.headline)
            Text("金额、币种、收支方向、分类与交易时间都可以修改。原截图和识别全文不会随账目保存。")
                .font(.footnote)
                .foregroundStyle(ArchiveTheme.inkSoft)
            if let receiptDraft {
                ForEach(receiptDraft.result.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(ArchiveTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(ArchiveTheme.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArchiveTheme.mintWash, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("receipt.editorReview")
    }

    private var amountCard: some View {
        SurfaceCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("金额")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    currencyMenu
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(CurrencyCatalog.symbol(for: currencyCode))
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(AppTheme.gold)

                    TextField("0.00", text: $amountText)
                        .font(.system(size: amountFontSize, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .amount)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("金额，\(currencyCode)")
                }

                HStack(alignment: .center) {
                    kindSwitch
                    Spacer(minLength: 8)
                    if let amountValidationMessage {
                        Text(amountValidationMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.coral)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private var kindSwitch: some View {
        HStack(spacing: 2) {
            ForEach(TransactionKind.allCases, id: \.self) { item in
                Button {
                    guard kind != item else { return }
                    Haptics.select()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        kind = item
                    }
                } label: {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            kind == item
                                ? (item == .expense ? AppTheme.coral : AppTheme.accent)
                                : AppTheme.textTertiary
                        )
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background {
                            if kind == item {
                                Capsule(style: .continuous)
                                    .fill(
                                        (item == .expense ? AppTheme.coral : AppTheme.accent).opacity(0.12)
                                    )
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
    }

    private var currencyMenu: some View {
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
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(Capsule(style: .continuous).fill(AppTheme.surface.opacity(0.7)))
            .overlay(Capsule(style: .continuous).strokeBorder(AppTheme.separator.opacity(0.8), lineWidth: 0.8))
        }
        .accessibilityLabel("选择币种，当前 \(currencyCode)")
    }

    // MARK: - Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "分类", eyebrow: "Category")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 130 : 72), spacing: 8)], spacing: 14) {
                ForEach(categoryOptions) { option in
                    categoryChip(option)
                }

                Button {
                    Haptics.tap()
                    showingCategoryCreator = true
                } label: {
                    VStack(spacing: 7) {
                        ZStack {
                            Circle()
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(AppTheme.gold.opacity(0.55))
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.gold)
                        }
                        .frame(width: 44, height: 44)

                        Text("新建")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func categoryChip(_ option: CategoryOption) -> some View {
        let isSelected = option.id == categoryRaw

        return Button {
            Haptics.tap()
            categoryRaw = option.id
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(option.color.opacity(isSelected ? 0.22 : 0.10))
                    Circle()
                        .strokeBorder(isSelected ? option.color : Color.clear, lineWidth: 1.2)
                    Image(systemName: option.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(option.color)
                }
                .frame(width: 44, height: 44)

                Text(option.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var categoryOptions: [CategoryOption] {
        let base = kind == .expense
            ? CategoryCatalog.expenseOptions(custom: categoryStore.categories)
            : CategoryCatalog.incomeOptions(custom: categoryStore.categories)

        if base.contains(where: { $0.id == categoryRaw }) {
            return base
        }
        let fallback = CategoryCatalog.option(for: categoryRaw, kind: kind, custom: categoryStore.categories)
        return base + [fallback]
    }

    // MARK: - Channel

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "支付渠道", eyebrow: "Channel")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 150 : 90), spacing: 8)], spacing: 10) {
                ForEach(PaymentChannel.allCases, id: \.self) { item in
                    channelChip(item)
                }
            }
        }
    }

    private func channelChip(_ channelItem: PaymentChannel) -> some View {
        let isSelected = channel == channelItem

        return Button {
            Haptics.tap()
            channel = channelItem
        } label: {
            HStack(spacing: 6) {
                Image(systemName: channelItem.symbolName)
                    .font(.caption.weight(.medium))
                Text(channelItem.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? AppTheme.gold : AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AppTheme.gold.opacity(0.10) : AppTheme.surface.opacity(0.45))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.gold.opacity(0.45) : AppTheme.separator.opacity(0.7), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Details

    private var detailsCard: some View {
        SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                dateDetailsRow

                divider

                HStack(spacing: 10) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.gold)
                    TextField("备注（可选）", text: $note)
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .focused($focusedField, equals: .note)
                        .submitLabel(.done)
                        .accessibilityLabel("备注，可选")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                divider

                HStack(spacing: 10) {
                    Image(systemName: "storefront")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.gold)
                    TextField("商家（可选）", text: $merchant)
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .focused($focusedField, equals: .merchant)
                        .submitLabel(.done)
                        .accessibilityLabel("商家，可选")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
        }
    }

    private var dateDetailsRow: some View {
        let stacked = receiptDraft != nil && dynamicTypeSize >= .xxxLarge
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Label("日期", systemImage: "calendar")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            if !stacked { Spacer(minLength: 4) }
            DatePicker("记录日期", selection: $occurredAt, displayedComponents: receiptDraft == nil ? [.date] : [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(ArchiveTheme.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.separator.opacity(0.55))
            .frame(height: 0.7)
            .padding(.leading, 38)
    }

    // MARK: - Save

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button {
                save()
            } label: {
                HStack {
                    Text(receiptDraft != nil ? "确认保存" : editingTransaction == nil ? "保存记录" : "保存修改")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "checkmark")
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
            .accessibilityIdentifier(receiptDraft == nil ? "finance.saveRecord" : "receipt.confirmSave")
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(ArchiveTheme.paperRaised.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Logic

    private var parsedMinorUnits: Int? {
        MoneyParser.minorUnits(from: amountText, currencyCode: currencyCode)
    }

    private var canSave: Bool {
        guard !didSave else { return false }
        guard let parsedMinorUnits else { return false }
        return parsedMinorUnits > 0
    }

    private var amountValidationMessage: String? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parsedMinorUnits else {
            return "金额格式不正确，请检查小数位"
        }
        if parsedMinorUnits <= 0 {
            return "金额需要大于 0"
        }
        return nil
    }

    private func adjustCategory(for newKind: TransactionKind) {
        let options = newKind == .expense
            ? CategoryCatalog.expenseOptions(custom: categoryStore.categories)
            : CategoryCatalog.incomeOptions(custom: categoryStore.categories)
        if !options.contains(where: { $0.id == categoryRaw }) {
            categoryRaw = newKind == .expense
                ? BuiltInCategory.dining.rawValue
                : (CategoryCatalog.incomeCategories.first?.id ?? "其他收入")
        }
    }

    private func save() {
        persist(allowPossibleDuplicate: false)
    }

    private func persist(allowPossibleDuplicate: Bool) {
        guard !didSave else { return }
        guard let minor = parsedMinorUnits, minor > 0 else { return }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)

        if let receiptDraft, editingTransaction == nil {
            let check = ReceiptDuplicateMatcher.check(
                amountMinor: minor, currencyCode: currencyCode, kind: kind,
                occurredAt: occurredAt, merchant: trimmedMerchant,
                externalID: receiptDraft.result.externalID, existing: existingTransactions,
                hasExplicitTime: receiptTimeWasEdited || receiptDraft.result.hasExplicitTime
            )
            if check.hasExactMatch {
                operationError = "这张截图或同一交易号已记过，不会重复保存。请回到账目中查看或编辑原记录。"
                return
            }
            if check.hasPossibleMatch && !allowPossibleDuplicate {
                receiptDuplicateMessage = "已有同金额、币种和商家的相近时间记录，或同一交易号的其他收支。请核对日期、金额与退款情况，确认是另一笔交易后再保存。"
                showingPossibleReceiptDuplicate = true
                return
            }
        }

        if let editingTransaction {
            editingTransaction.amountMinor = minor
            editingTransaction.currencyCode = currencyCode.uppercased()
            editingTransaction.kind = kind
            editingTransaction.categoryRaw = categoryRaw
            editingTransaction.channel = channel
            editingTransaction.occurredAt = occurredAt
            editingTransaction.note = trimmedNote
            editingTransaction.merchant = trimmedMerchant
            editingTransaction.updatedAt = .now
        } else {
            let transaction = MoneyTransaction(
                amountMinor: minor,
                currencyCode: currencyCode,
                kind: kind,
                categoryRaw: categoryRaw,
                channel: channel,
                occurredAt: occurredAt,
                note: trimmedNote,
                merchant: trimmedMerchant,
                externalID: receiptDraft?.result.externalID
            )
            context.insert(transaction)
        }

        do {
            try context.save()
            didSave = true
            Haptics.success()
            dismiss()
        } catch {
            context.rollback()
            operationError = "记录未能保存，填写的内容仍在。请重试。\n\(error.localizedDescription)"
        }
    }

    private func deleteTransaction() {
        guard let editingTransaction else { return }
        context.delete(editingTransaction)
        do {
            try context.save()
            Haptics.success()
            dismiss()
        } catch {
            context.rollback()
            operationError = "删除失败，记录已保留。请重试。\n\(error.localizedDescription)"
        }
    }

    private static func amountString(minorUnits: Int, currencyCode: String) -> String {
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
