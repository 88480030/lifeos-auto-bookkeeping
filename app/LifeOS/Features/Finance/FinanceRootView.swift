import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct FinanceRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \MoneyTransaction.occurredAt, order: .reverse)
    private var allTransactions: [MoneyTransaction]

    @Query(sort: \Budget.monthKey)
    private var budgets: [Budget]

    @StateObject private var categoryStore = CustomCategoryStore()

    @State private var section: FinanceSection
    @State private var month: Date = {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
    }()
    @State private var currencyCode = "CNY"
    @State private var showingAddTransaction = false
    @State private var editingTransaction: MoneyTransaction?
    @State private var transactionToDelete: MoneyTransaction?
    @State private var showingBudgetEditor = false
    @State private var showingDataActions = false
    @State private var pendingDataAction: FinanceDataAction?
    @State private var showingFileImporter = false
    @State private var fileImportKind: FinanceFileImportKind = .statement
    @State private var showingPaymentSources = false
    @State private var importAfterSourcesDismissal = false
    @State private var showingBackupExporter = false
    @State private var statementPreview: StatementPreviewItem?
    @State private var backupDocument: BackupFileDocument?
    @State private var alertMessage: String?
    @State private var lastNavigationRequestID: UUID?
    @State private var recordListIdentity = UUID()
    @State private var requestedFinanceDate: Date?
    @State private var automaticReceiptNotice: String?
    @State private var receiptCaptureInput: ReceiptCaptureRequest?
    @State private var queuedReceiptInput: ReceiptCaptureRequest?
    @State private var pendingReceiptDraft: ReceiptEditorDraft?
    @State private var receiptEditorDraft: ReceiptEditorDraft?

    #if DEBUG
    private let autoOpenEditor = ProcessInfo.processInfo.arguments.contains("-openTransactionEditor")
    private let autoShowImportPreview = ProcessInfo.processInfo.arguments.contains("-openImportPreview")
    @State private var didAutoOpenEditor = false
    @State private var didAutoShowImportPreview = false
    @State private var didAutoOpenReceipt = false
    #endif

    init() {
        var initialSection: FinanceSection = .records
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-financeSection"),
           arguments.indices.contains(index + 1),
           let parsed = FinanceSection(rawValue: arguments[index + 1]) {
            initialSection = parsed
        }
        #endif
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        monthBar

                        FinanceSegmentedControl(selection: $section)

                        if section == .records {
                            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                                DailySpendingPanel(transactions: allTransactions, date: timeline.date, currencyCode: currencyCode)
                            }
                        }

                        sectionContent
                        MangaPageFooter(page: "02")
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.top, 10)
                    .padding(.bottom, 150)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(initialScrollAnchor)
            }
            .overlay(alignment: .top) {
                if let automaticReceiptNotice {
                    Label(automaticReceiptNotice, systemImage: automaticReceiptNotice.hasPrefix("未") ? "exclamationmark.circle" : "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(ArchiveTheme.ink)
                        .padding(16)
                        .background(ArchiveTheme.mintWash, in: Capsule())
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("finance.automaticReceiptNotice")
                }
            }
            .task(id: automaticReceiptNotice) {
                guard let message = automaticReceiptNotice else { return }
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                if automaticReceiptNotice == message { automaticReceiptNotice = nil }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingDataActions, onDismiss: performPendingDataAction) {
                dataActionsPanel
            }
            .sheet(isPresented: $showingAddTransaction, onDismiss: presentQueuedReceiptIfPossible) {
                TransactionEditorView(
                    transaction: nil,
                    defaultCurrencyCode: currencyCode,
                    categoryStore: categoryStore
                )
            }
            .sheet(item: $editingTransaction, onDismiss: presentQueuedReceiptIfPossible) { transaction in
                TransactionEditorView(
                    transaction: transaction,
                    defaultCurrencyCode: currencyCode,
                    categoryStore: categoryStore
                )
            }
            .sheet(isPresented: $showingBudgetEditor, onDismiss: presentQueuedReceiptIfPossible) {
                BudgetEditorView(
                    month: month,
                    currencyCode: currencyCode,
                    existingBudget: monthBudget
                )
            }
            .sheet(isPresented: $showingPaymentSources, onDismiss: {
                if importAfterSourcesDismissal {
                    importAfterSourcesDismissal = false
                    fileImportKind = .statement
                    showingFileImporter = true
                } else {
                    presentQueuedReceiptIfPossible()
                }
            }) {
                PaymentSourcesView(
                    transactions: allTransactions,
                    onImportStatement: {
                        importAfterSourcesDismissal = true
                        showingPaymentSources = false
                    },
                    onRecognizeScreenshot: {
                        queuedReceiptInput = ReceiptCaptureRequest()
                        showingPaymentSources = false
                    }
                )
            }
            .sheet(item: $statementPreview, onDismiss: presentQueuedReceiptIfPossible) { item in
                StatementImportPreviewView(
                    result: item.result,
                    existingExternalIDs: existingExternalIDs,
                    existingTransactions: allTransactions
                ) { transactions in
                    importStatements(transactions)
                }
            }
            .sheet(item: $receiptCaptureInput, onDismiss: {
                if let draft = pendingReceiptDraft {
                    pendingReceiptDraft = nil
                    receiptEditorDraft = draft
                } else {
                    presentQueuedReceiptIfPossible()
                }
            }) { input in
                ReceiptCaptureView(
                    initialImageData: input.imageData,
                    automaticallySave: input.automaticallySave,
                    onAutomaticRecord: { message in
                        automaticReceiptNotice = message
                        receiptCaptureInput = nil
                    }
                ) { draft in
                    pendingReceiptDraft = draft
                    receiptCaptureInput = nil
                }
            }
            .sheet(item: $receiptEditorDraft, onDismiss: presentQueuedReceiptIfPossible) { draft in
                TransactionEditorView(
                    transaction: nil,
                    defaultCurrencyCode: draft.selectedAmount?.currencyCode ?? "CNY",
                    categoryStore: categoryStore,
                    receiptDraft: draft
                )
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: fileImportKind.contentTypes
            ) { result in
                switch result {
                case .success(let url):
                    switch fileImportKind {
                    case .statement: handleStatementFile(url)
                    case .backup: handleBackupFile(url)
                    }
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError {
                        alertMessage = error.localizedDescription
                    }
                }
            }
            .fileExporter(
                isPresented: $showingBackupExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: backupFileName
            ) { result in
                switch result {
                case .success:
                    alertMessage = "备份已导出。\n请把文件保存到「文件」App 或 iCloud Drive。"
                case .failure(let error):
                    alertMessage = "导出失败：\(error.localizedDescription)"
                }
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好") { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
            .confirmationDialog("删除这笔记录？", isPresented: Binding(
                get: { transactionToDelete != nil },
                set: { if !$0 { transactionToDelete = nil } }
            ), titleVisibility: .visible, presenting: transactionToDelete) { transaction in
                Button("删除记录", role: .destructive) {
                    delete(transaction)
                    transactionToDelete = nil
                }
                Button("取消", role: .cancel) { transactionToDelete = nil }
            } message: { transaction in
                Text("\(FinanceFormatting.signedAmount(transaction)) · \(transaction.categoryDisplayName)\n删除后无法恢复。")
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-openReceiptCapture"), !didAutoOpenReceipt {
                    didAutoOpenReceipt = true
                    let data = ProcessInfo.processInfo.arguments.contains("-receiptFixture") ? ReceiptDebugSample.imageData() : nil
                    queuedReceiptInput = ReceiptCaptureRequest(imageData: data)
                    presentQueuedReceiptIfPossible()
                }
                if autoOpenEditor && !didAutoOpenEditor {
                    didAutoOpenEditor = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        showingAddTransaction = true
                    }
                }
                if autoShowImportPreview && !didAutoShowImportPreview {
                    didAutoShowImportPreview = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if let result = DebugSamples.parseSample() {
                            statementPreview = StatementPreviewItem(result: result)
                        }
                    }
                }
                #endif
            }
            .onChange(of: showingFileImporter) { _, visible in
                if !visible { presentQueuedReceiptIfPossible() }
            }
            .onChange(of: showingBackupExporter) { _, visible in
                if !visible { presentQueuedReceiptIfPossible() }
            }
            .onReceive(ReceiptCaptureCenter.shared.$request) { request in
                guard let request else { return }
                queuedReceiptInput = request
                ReceiptCaptureCenter.shared.clear()
                presentQueuedReceiptIfPossible()
            }
            .onReceive(AppNavigationCenter.shared.$request) { request in
                guard let request, request.id != lastNavigationRequestID,
                      case .financeRecords = request.action else { return }
                lastNavigationRequestID = request.id
                if let date = request.scheduleDate {
                    requestedFinanceDate = date
                    section = .calendar
                    month = FinanceAnalytics.monthInterval(containing: date).start
                    let dayRecords = allTransactions.filter {
                        Calendar.current.isDate($0.occurredAt, inSameDayAs: date)
                    }
                    let expenseCurrencies = Set(dayRecords.filter { $0.kind == .expense }.map { $0.currencyCode.uppercased() })
                    let dayCurrencies = expenseCurrencies.isEmpty
                        ? Set(dayRecords.map { $0.currencyCode.uppercased() }) : expenseCurrencies
                    if !dayCurrencies.contains(currencyCode) {
                        currencyCode = dayCurrencies.contains("CNY") ? "CNY" : (dayCurrencies.sorted().first ?? currencyCode)
                    }
                } else {
                    requestedFinanceDate = nil
                    section = .records
                    month = FinanceAnalytics.monthInterval(containing: .now).start
                }
                recordListIdentity = UUID()
            }
        }
    }

    // MARK: - Header

    /// 仅 DEBUG 截图使用：`-scrollBottom` 时初始滚动到底部。
    private var initialScrollAnchor: UnitPoint {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-scrollBottom") {
            return .bottom
        }
        #endif
        return .top
    }

    private var monthTotals: FinanceTotals {
        FinanceAnalytics.totals(
            monthTransactions,
            in: FinanceAnalytics.monthInterval(containing: month),
            currencyCode: currencyCode
        )
    }

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))

        return layout {
            VStack(alignment: .leading, spacing: 6) {
                MangaCaptionTag(
                    text: "FINANCE FILE",
                    fill: ArchiveTheme.ink,
                    rotation: -1.2
                )

                Text("财务档案")
                    .font(.system(.largeTitle, design: .rounded).weight(.black))
                    .foregroundStyle(ArchiveTheme.ink)

                Text("\(AppFormatters.monthTitle(month)) · \(monthTransactions.count) 笔 · \(currencyCode)")
                    .font(.archiveMono)
                    .foregroundStyle(ArchiveTheme.inkSoft)
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 4)
            }

            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 6) {
                Text("本月结余")
                    .font(.caption)
                    .foregroundStyle(ArchiveTheme.inkSoft)

                Text(MoneyFormatter.string(minorUnits: monthTotals.balanceMinor, currencyCode: currencyCode))
                    .font(.system(.title3, design: .serif).weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(monthTotals.balanceMinor >= 0 ? ArchiveTheme.ink : AppTheme.coral)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                HStack(spacing: 6) {
                    dataMenu
                    receiptButton
                    addRecordButton
                }
            }
        }
    }

    private var addRecordButton: some View {
        Button {
            Haptics.tap()
            showingAddTransaction = true
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.goldBright, AppTheme.gold],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1A1206))
            }
            .frame(width: 46, height: 46)
            .shadow(color: AppTheme.gold.opacity(0.30), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel("添加记录")
    }

    private var receiptButton: some View {
        Button {
            Haptics.tap()
            queuedReceiptInput = ReceiptCaptureRequest()
            presentQueuedReceiptIfPossible()
        } label: {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ArchiveTheme.ink)
                .frame(width: 44, height: 44)
                .background(ArchiveTheme.mintWash, in: Circle())
        }
        .buttonStyle(DepthPressStyle())
        .accessibilityLabel("截图记账")
        .accessibilityHint("选择付款截图，本机识别后核对保存")
        .accessibilityIdentifier("finance.captureReceipt")
    }

    private func presentQueuedReceiptIfPossible() {
        guard let input = queuedReceiptInput,
              receiptCaptureInput == nil, receiptEditorDraft == nil,
              !showingAddTransaction, editingTransaction == nil,
              !showingBudgetEditor, !showingPaymentSources, !showingDataActions,
              statementPreview == nil, !showingFileImporter, !showingBackupExporter else { return }
        queuedReceiptInput = nil
        receiptCaptureInput = input
    }

    private enum FinanceFileImportKind {
        case statement, backup

        var contentTypes: [UTType] {
            switch self {
            case .statement: [.commaSeparatedText, .plainText, .text]
            case .backup: [.json]
            }
        }
    }

    private enum FinanceDataAction: String, CaseIterable, Identifiable {
        case receipt, sources, statementImport, backupExport, backupImport

        var id: Self { self }

        var title: String {
            switch self {
            case .receipt: "付款截图识别"
            case .sources: "账单来源说明"
            case .statementImport: "导入微信 / 支付宝账单"
            case .backupExport: "导出本地备份"
            case .backupImport: "导入本地备份"
            }
        }

        var symbol: String {
            switch self {
            case .receipt: "doc.text.viewfinder"
            case .sources: "doc.text"
            case .statementImport: "tray.and.arrow.down"
            case .backupExport: "square.and.arrow.up"
            case .backupImport: "tray.and.arrow.up"
            }
        }
    }

    private var dataMenu: some View {
        Button {
            Haptics.tap()
            showingDataActions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(AppTheme.surface.opacity(0.6)))
                .overlay(Circle().strokeBorder(AppTheme.separator.opacity(0.7), lineWidth: 0.8))
        }
        .accessibilityLabel("账单来源、导入与备份")
        .accessibilityIdentifier("finance.dataActions")
    }

    private var dataActionsPanel: some View {
        NavigationStack {
            List(FinanceDataAction.allCases) { action in
                Button {
                    pendingDataAction = action
                    showingDataActions = false
                } label: {
                    Label(action.title, systemImage: action.symbol)
                        .foregroundStyle(ArchiveTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("finance.dataAction.\(action.rawValue)")
                .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("账单与数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { showingDataActions = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Only present a destination after the action panel has finished dismissing.
    /// Opening a second presentation inside a native Menu action can be swallowed on iOS 26.
    private func performPendingDataAction() {
        guard let action = pendingDataAction else {
            presentQueuedReceiptIfPossible()
            return
        }
        pendingDataAction = nil
        switch action {
        case .receipt:
            queuedReceiptInput = ReceiptCaptureRequest()
            presentQueuedReceiptIfPossible()
        case .sources:
            showingPaymentSources = true
        case .statementImport:
            fileImportKind = .statement
            showingFileImporter = true
        case .backupExport:
            exportBackup()
        case .backupImport:
            fileImportKind = .backup
            showingFileImporter = true
        }
    }

    // MARK: - Month bar

    private var monthBar: some View {
        HStack(spacing: 10) {
            monthChevron(systemName: "chevron.left", label: "上个月") { shiftMonth(-1) }

            Text(AppFormatters.monthTitle(month))
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .contentTransition(.numericText())

            monthChevron(systemName: "chevron.right", label: "下个月") { shiftMonth(1) }

            Spacer()

            if availableCurrencies.count > 1 {
                currencyMenu
            } else {
                Text(currencyCode)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(AppTheme.surface.opacity(0.4)))
            }
        }
    }

    private func monthChevron(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                action()
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(AppTheme.surface.opacity(0.55)))
                .overlay(Circle().strokeBorder(AppTheme.separator.opacity(0.7), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var currencyMenu: some View {
        Menu {
            ForEach(availableCurrencies, id: \.self) { code in
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
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(Capsule(style: .continuous).fill(AppTheme.surface.opacity(0.55)))
            .overlay(Capsule(style: .continuous).strokeBorder(AppTheme.separator.opacity(0.75), lineWidth: 0.8))
        }
        .accessibilityLabel("选择币种，当前 \(currencyCode)")
    }

    // MARK: - Content

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .records:
            FinanceRecordsView(
                transactions: monthTransactions,
                month: month,
                currencyCode: currencyCode,
                categories: categoryStore,
                onEdit: { editingTransaction = $0 },
                onDelete: { transactionToDelete = $0 },
                onAdd: { showingAddTransaction = true }
            )
            .id(recordListIdentity)
        case .calendar:
            FinanceCalendarView(
                transactions: monthTransactions,
                month: month,
                currencyCode: currencyCode,
                categories: categoryStore,
                onEdit: { editingTransaction = $0 },
                onDelete: { transactionToDelete = $0 },
                initialSelectedDate: requestedFinanceDate
            )
            .id(recordListIdentity)
        case .stats:
            FinanceStatisticsView(
                allTransactions: allTransactions,
                month: month,
                currencyCode: currencyCode,
                budgets: budgets,
                categories: categoryStore,
                onSetBudget: { showingBudgetEditor = true },
                onEdit: { editingTransaction = $0 }
            )
        }
    }

    // MARK: - Data

    private var availableCurrencies: [String] {
        let set = Set(allTransactions.map { $0.currencyCode.uppercased() })
            .union(budgets.map { $0.currencyCode.uppercased() })
        var codes = ["CNY"]
        codes.append(contentsOf: set.subtracting(["CNY"]).sorted())
        return codes
    }

    private var monthTransactions: [MoneyTransaction] {
        let interval = FinanceAnalytics.monthInterval(containing: month)
        let code = currencyCode.uppercased()
        return allTransactions.filter {
            $0.currencyCode.uppercased() == code
                && $0.occurredAt >= interval.start && $0.occurredAt < interval.end
        }
    }

    private var monthBudget: Budget? {
        let key = DayKey.monthKey(for: month)
        let code = currencyCode.uppercased()
        return budgets.first {
            $0.monthKey == key && $0.currencyCode.uppercased() == code
        }
    }

    private func shiftMonth(_ delta: Int) {
        guard let newMonth = Calendar.current.date(byAdding: .month, value: delta, to: month) else { return }
        month = newMonth
    }

    private var existingExternalIDs: Set<String> {
        Set(allTransactions.compactMap { $0.externalID }.filter { !$0.isEmpty })
    }

    private var backupFileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "LifeOS-Backup-\(formatter.string(from: .now))"
    }

    private func handleStatementFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let result = try StatementImporter.parse(data: data, fileName: url.lastPathComponent)
            statementPreview = StatementPreviewItem(result: result)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func importStatements(_ transactions: [ImportedTransaction]) {
        guard !transactions.isEmpty else { return }
        do {
            let current = try context.fetch(FetchDescriptor<MoneyTransaction>())
            var identifiers = Set(current.compactMap(\.externalID))
            let accepted = transactions.filter { item in
                guard !identifiers.contains(item.externalID),
                      !ReceiptDuplicateMatcher.isExactImportDuplicate(item, existing: current) else { return false }
                identifiers.insert(item.externalID)
                return true
            }
            guard !accepted.isEmpty else {
                alertMessage = "没有需要新增的记录，同一交易已在账目中。"
                return
            }
            for item in accepted {
            context.insert(
                MoneyTransaction(
                    amountMinor: item.amountMinor,
                    currencyCode: item.currencyCode,
                    kind: item.kind,
                    categoryRaw: item.categoryRaw,
                    channel: item.channel,
                    occurredAt: item.occurredAt,
                    note: item.note,
                    merchant: item.merchant,
                    externalID: item.externalID
                )
            )
            }
            try context.save()
            Haptics.success()
            alertMessage = "成功导入 \(accepted.count) 笔记录。\n重复记录已自动跳过。"
        } catch {
            context.rollback()
            alertMessage = "账单未能导入，原记录已保留。请重新选择账单重试。\n\(error.localizedDescription)"
        }
    }

    private func exportBackup() {
        do {
            let archive = try BackupService.makeArchive(context: context, categories: categoryStore.categories)
            backupDocument = BackupFileDocument(data: try archive.encoded())
            showingBackupExporter = true
        } catch {
            alertMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func handleBackupFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let archive = try BackupArchive.decoded(from: data)
            let summary = try BackupService.importArchive(
                archive,
                context: context,
                categoryStore: categoryStore
            )
            alertMessage = summary.text
            Haptics.success()
        } catch {
            alertMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func delete(_ transaction: MoneyTransaction) {
        context.delete(transaction)
        do {
            try context.save()
            Haptics.success()
        } catch {
            context.rollback()
            alertMessage = "删除失败，记录已保留。请重试。\n\(error.localizedDescription)"
        }
    }
}
