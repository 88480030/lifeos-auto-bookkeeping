import ImageIO
import PhotosUI
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 手动入口生成草稿；快捷指令入口可自动保存可靠结果。图片与全文不持久化。
struct ReceiptCaptureView: View {
    let initialImageData: Data?
    let automaticallySave: Bool
    let onReview: (ReceiptEditorDraft) -> Void
    let onAutomaticRecord: ((String) -> Void)?

    @Environment(\.modelContext) private var context
    @AppStorage("receiptShortcutAutoSave") private var shortcutAutoSaveEnabled = true
    @State private var automaticOutcome: ReceiptAutomaticRecordOutcome?
    @State private var capturedAt = Date.now

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var photoItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var recognitionTask: Task<Void, Never>?
    @State private var activeJobID = UUID()
    @State private var isProcessing = false
    @State private var isHandingOff = false
    @State private var didLoadInitialImage = false
    @State private var imageData: Data?
    @State private var previewImage: UIImage?
    @State private var recognizedLines: [String] = []
    @State private var result: ReceiptParseResult?
    @State private var selectedAmountID: String?
    @State private var operationError: String?

    init(initialImageData: Data? = nil, automaticallySave: Bool = false, onAutomaticRecord: ((String) -> Void)? = nil, onReview: @escaping (ReceiptEditorDraft) -> Void) {
        self.initialImageData = initialImageData
        self.automaticallySave = automaticallySave
        self.onReview = onReview
        self.onAutomaticRecord = onAutomaticRecord
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    introduction
                    if automaticallySave {
                        Toggle("快捷指令自动记账", isOn: $shortcutAutoSaveEnabled)
                            .tint(ArchiveTheme.ink)
                            .accessibilityIdentifier("receipt.automaticSave")
                    }
                    imageSelectors
                    if let previewImage { imagePreview(previewImage) }
                    if isProcessing { processingState }
                    if let operationError { errorState(operationError) }
                    if let automaticOutcome { automaticStatus(automaticOutcome) }
                    if let result, !automaticRecordFinished, !automaticRecordFailed { review(result) }
                    privacyNote
                }
                .padding(AppTheme.pagePadding)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .background(ArchiveTheme.paper)
            .foregroundStyle(ArchiveTheme.ink)
            .navigationTitle("截图记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        cancelRecognition()
                        dismiss()
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(ArchiveTheme.ink)
                    .accessibilityLabel("关闭截图记账")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if automaticRecordFinished || automaticRecordFailed {
                    Button("关闭") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(ArchiveTheme.ink)
                        .padding()
                } else if let result, !isProcessing { reviewActions(result) }
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image]) { response in
                switch response {
                case .success(let url): loadFile(url)
                case .failure(let error):
                    guard (error as NSError).code != NSUserCancelledError else { return }
                    cancelRecognition()
                    clearRecognizedImage()
                    operationError = "文件未能打开，请重试。\n" + error.localizedDescription
                }
            }
            .onChange(of: photoItem) { _, item in
                if let item { loadPhoto(item) }
            }
            .task {
                guard !didLoadInitialImage else { return }
                didLoadInitialImage = true
                if let initialImageData { loadImageData(initialImageData) }
            }
            .onDisappear {
                cancelRecognition()
                clearRecognizedImage()
                operationError = nil
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("receipt.capture")
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "doc.text.viewfinder")
                .font(.title2.weight(.medium))
                .frame(width: 52, height: 52)
                .background(ArchiveTheme.mintWash, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(automaticallySave && shortcutAutoSaveEnabled ? "本机识别，自动记账" : "本机识别，确认后记账")
                    .font(.title3.weight(.bold))
                Text(automaticallySave && shortcutAutoSaveEnabled ? "识别成功直接保存，同金额不再询问；明确重复的交易自动跳过。" : "选择付款详情截图，先核对金额、商家和日期，再编辑分类并保存。")
                    .font(.subheadline)
                    .foregroundStyle(ArchiveTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var imageSelectors: some View {
        let photoTitle = previewImage == nil ? "从相册选择" : "更换截图"
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Label(photoTitle, systemImage: "photo")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.horizontal, 10)
                    .foregroundStyle(ArchiveTheme.stripInk)
                    .background(ArchiveTheme.strip, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PressableScaleStyle())
            .disabled(isHandingOff)
            .accessibilityIdentifier("receipt.selectPhoto")

            Button {
                showingFileImporter = true
            } label: {
                Label("从文件选择", systemImage: "folder")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.horizontal, 10)
                    .background(ArchiveTheme.paperRaised, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ArchiveTheme.rule, lineWidth: 1))
            }
            .buttonStyle(PressableScaleStyle())
            .disabled(isHandingOff)
            .accessibilityIdentifier("receipt.selectFile")
        }
    }

    private func imagePreview(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: 220)
            .padding(12)
            .background(ArchiveTheme.paperTint, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("已选择的付款截图，可与下方识别结果核对")
    }

    private var processingState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().tint(ArchiveTheme.ink)
                Text("正在识别付款信息…").font(.subheadline.weight(.semibold))
            }
            Text("图片在本机处理，请稍候。")
                .font(.caption).foregroundStyle(ArchiveTheme.inkSoft)
            Button("取消识别") { cancelRecognition() }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .accessibilityIdentifier("receipt.cancelRecognition")
        }
        .accessibilityElement(children: .contain)
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("这次没有识别成功", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(ArchiveTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if let imageData {
                Button("重新识别") { loadImageData(imageData) }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("receipt.retry")
            }
            Text("也可以关闭此页，手动记一笔。")
                .font(.caption).foregroundStyle(ArchiveTheme.inkSoft)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArchiveTheme.goldWash, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("receipt.error")
    }

    private func review(_ parsed: ReceiptParseResult) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("核对识别结果").font(.title3.weight(.bold))
                Text(parsed.suggestedAmount == nil
                     ? "请选择截图中的实际金额，或在下一步手动补全。"
                     : "已选中建议金额，请对照原图确认。")
                    .font(.subheadline).foregroundStyle(ArchiveTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if parsed.amountCandidates.isEmpty {
                    Label("金额待填写", systemImage: "pencil")
                        .font(.headline).frame(minHeight: 44)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(parsed.amountCandidates.enumerated()), id: \.element.id) { index, candidate in
                            amountOption(candidate)
                            if index < parsed.amountCandidates.count - 1 { Divider().overlay(ArchiveTheme.rule) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(ArchiveTheme.paperRaised, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                detail("商家", value: parsed.merchant ?? "待填写")
                detail("日期", value: recognizedDate(parsed))
                detail("收支", value: parsed.kind.displayName)
                detail("支付方式", value: parsed.channel?.displayName ?? "待确认")
                detail("建议分类", value: parsed.kind == .income ? "其他收入" : (BuiltInCategory(rawValue: parsed.categoryRaw)?.displayName ?? parsed.categoryRaw))
            }

            if !parsed.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("需要你确认").font(.headline)
                    ForEach(Array(parsed.warnings.enumerated()), id: \.offset) { _, warning in
                        Label {
                            Text(warning).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.circle")
                        }
                        .font(.subheadline)
                        .foregroundStyle(ArchiveTheme.inkSoft)
                    }
                }
                .accessibilityIdentifier("receipt.warnings")
            }

            DisclosureGroup("查看识别文字") {
                Text(recognizedLines.joined(separator: "\n"))
                    .font(.footnote)
                    .foregroundStyle(ArchiveTheme.inkSoft)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
            .font(.subheadline.weight(.semibold))
            .tint(ArchiveTheme.ink)
            .accessibilityIdentifier("receipt.recognizedText")
        }
        .accessibilityIdentifier("receipt.review")
    }

    private func amountOption(_ candidate: ReceiptAmountCandidate) -> some View {
        let selected = selectedAmountID == candidate.id
        return Button {
            Haptics.select()
            selectedAmountID = candidate.id
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(MoneyFormatter.string(minorUnits: candidate.amountMinor, currencyCode: candidate.currencyCode))
                        .font(.title3.weight(.bold)).monospacedDigit()
                    Text(candidate.sourceText)
                        .font(.caption).foregroundStyle(ArchiveTheme.inkSoft)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if candidate.isPreferred {
                        Text("建议金额").font(.caption.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("金额候选，\(MoneyFormatter.string(minorUnits: candidate.amountMinor, currencyCode: candidate.currencyCode))，\(candidate.sourceText)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("receipt.amount.\(candidate.id)")
    }

    private func detail(_ title: String, value: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 18))
        return layout {
            Text(title).font(.subheadline).foregroundStyle(ArchiveTheme.inkSoft)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
            Text(value)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func reviewActions(_ parsed: ReceiptParseResult) -> some View {
        let selected = parsed.amountCandidates.first { $0.id == selectedAmountID }
        return VStack(spacing: 7) {
            Text("下一步仍可修改；点击保存时会检查重复记录。")
                .font(.caption)
                .foregroundStyle(ArchiveTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if parsed.amountCandidates.isEmpty {
                continueButton("手动补全", parsed: parsed, selected: nil, enabled: true)
            } else {
                continueButton("确认金额并编辑", parsed: parsed, selected: selected, enabled: selected != nil)
                Button("手动补全金额") { handOff(parsed, selected: nil) }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(isHandingOff)
                    .accessibilityIdentifier("receipt.manualComplete")
            }
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(ArchiveTheme.paper)
        .overlay(alignment: .top) { Divider().overlay(ArchiveTheme.rule) }
    }

    private func continueButton(_ title: String, parsed: ReceiptParseResult, selected: ReceiptAmountCandidate?, enabled: Bool) -> some View {
        Button { handOff(parsed, selected: selected) } label: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 12)
                .foregroundStyle(enabled ? ArchiveTheme.stripInk : ArchiveTheme.inkSoft)
                .background(enabled ? ArchiveTheme.strip : ArchiveTheme.paperTint, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(!enabled || isHandingOff)
        .accessibilityIdentifier("receipt.continue")
    }

    private var automaticRecordFailed: Bool {
        if case .needsReview = automaticOutcome { return true }
        return false
    }

    private var automaticRecordFinished: Bool {
        switch automaticOutcome {
        case .saved, .duplicate: true
        default: false
        }
    }

    private func automaticStatus(_ outcome: ReceiptAutomaticRecordOutcome) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch outcome {
            case .saved:
                Label("已自动记账", systemImage: "checkmark.circle.fill")
                    .font(.title2.bold())
                if let amount = result?.suggestedAmount {
                    Text(MoneyFormatter.string(minorUnits: amount.amountMinor, currencyCode: amount.currencyCode))
                        .font(.largeTitle.bold()).monospacedDigit()
                }
                Text([result?.merchant, result?.kind == .income ? "其他收入" : result?.categoryRaw]
                    .compactMap { $0 }.joined(separator: " · "))
                Text("已保存到财务档案，可在记账页修改或删除。")
                if result?.occurredAt == nil { Text("未识别日期，已按本次截图时刻记录。") }
            case .duplicate:
                Label("这笔交易已记过", systemImage: "checkmark.shield")
                    .font(.headline)
                Text("已跳过，不会重复记账。")
            case .needsReview:
                Label("本次未自动录入", systemImage: "exclamationmark.circle")
                    .font(.headline)
                Text("没有识别到明确的已完成付款金额，没有新增账目。上方是快捷指令实际传来的图片，下方是本机识别结果。")
                Text("本机识别文字").font(.subheadline.bold())
                Text(recognizedLines.joined(separator: "\n"))
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("receipt.failureText")
                Text("关闭后清除本次图片和识别文字；不会上传。")
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(ArchiveTheme.mintWash, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("receipt.automaticResult")
    }

    private var privacyNote: some View {
        Label {
            Text(automaticallySave && shortcutAutoSaveEnabled ? "图片和识别文字仅在本机临时处理，不会上传。自动保存的账目可在记账页编辑或删除。未识别日期时按截图时刻记录。" : "图片和识别文字仅在本机临时处理，不会上传；只有你确认保存后才会新增账目。")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield")
        }
        .font(.footnote)
        .foregroundStyle(ArchiveTheme.inkSoft)
    }

    private func recognizedDate(_ parsed: ReceiptParseResult) -> String {
        guard let date = parsed.occurredAt else { return "待填写" }
        return date.formatted(date: .numeric, time: parsed.hasExplicitTime ? .shortened : .omitted)
    }

    private func handOff(_ parsed: ReceiptParseResult, selected: ReceiptAmountCandidate?) {
        guard !isHandingOff else { return }
        isHandingOff = true
        Haptics.tap()
        onReview(ReceiptEditorDraft(result: parsed, selectedAmount: selected))
    }

    private func beginRecognition() -> UUID {
        recognitionTask?.cancel()
        let jobID = UUID()
        activeJobID = jobID
        isProcessing = true
        operationError = nil
        automaticOutcome = nil
        capturedAt = .now
        clearRecognizedImage()
        return jobID
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        let jobID = beginRecognition()
        recognitionTask = Task { @MainActor in
            defer { completeJob(jobID) }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ReceiptRecognitionError.invalidImage
                }
                try await recognize(data, jobID: jobID)
            } catch is CancellationError {
                // A new selection or closing the sheet cancels this job.
            } catch {
                if activeJobID == jobID { operationError = error.localizedDescription }
            }
        }
    }

    private func loadFile(_ url: URL) {
        let jobID = beginRecognition()
        let limit = ReceiptTextRecognizer.maximumFileBytes
        recognitionTask = Task { @MainActor in
            defer { completeJob(jobID) }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > limit {
                        throw ReceiptRecognitionError.imageTooLarge
                    }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard data.count <= limit else { throw ReceiptRecognitionError.imageTooLarge }
                    return data
                }.value
                try await recognize(data, jobID: jobID)
            } catch is CancellationError {
            } catch {
                if activeJobID == jobID { operationError = error.localizedDescription }
            }
        }
    }

    private func loadImageData(_ data: Data) {
        let jobID = beginRecognition()
        recognitionTask = Task { @MainActor in
            defer { completeJob(jobID) }
            do {
                try await recognize(data, jobID: jobID)
            } catch is CancellationError {
            } catch {
                if activeJobID == jobID { operationError = error.localizedDescription }
            }
        }
    }

    private func recognize(_ data: Data, jobID: UUID) async throws {
        try Task.checkCancellation()
        guard activeJobID == jobID else { throw CancellationError() }
        guard data.count <= ReceiptTextRecognizer.maximumFileBytes else { throw ReceiptRecognitionError.imageTooLarge }
        imageData = data
        let lines = try await ReceiptTextRecognizer.recognize(imageData: data)
        try Task.checkCancellation()
        guard activeJobID == jobID else { throw CancellationError() }
        // Vision 已校验图片尺寸；缩图与 PNG 编码继续留在工作线程，避免阻塞交互。
        let thumbnail = await Task.detached(priority: .userInitiated) {
            Self.previewData(from: data)
        }.value
        try Task.checkCancellation()
        guard activeJobID == jobID else { throw CancellationError() }
        let parsed = ReceiptParser.parse(lines: lines)
        previewImage = thumbnail.flatMap { UIImage(data: $0) }
        recognizedLines = lines
        result = parsed
        selectedAmountID = parsed.suggestedAmount?.id
        if automaticallySave && shortcutAutoSaveEnabled {
            try Task.checkCancellation()
            guard activeJobID == jobID else { throw CancellationError() }
            automaticOutcome = try ReceiptAutomaticRecorder.record(parsed, in: context, capturedAt: capturedAt)
            switch automaticOutcome {
            case .saved:
                Haptics.success()
                if let amount = parsed.suggestedAmount {
                    onAutomaticRecord?("已自动记账 " + MoneyFormatter.string(minorUnits: amount.amountMinor, currencyCode: amount.currencyCode))
                }
            case .duplicate:
                onAutomaticRecord?("这笔交易已记过，已跳过")
            case .needsReview:
                // Keep the actual input visible on failure so a shortcut capture
                // mismatch can be distinguished from OCR or parser rejection.
                // Success still saves and dismisses without any confirmation.
                break
            default: break
            }
        }
    }

    private func completeJob(_ jobID: UUID) {
        guard activeJobID == jobID else { return }
        isProcessing = false
        photoItem = nil
        recognitionTask = nil
    }

    private func cancelRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        activeJobID = UUID()
        isProcessing = false
        photoItem = nil
    }

    private func clearRecognizedImage() {
        imageData = nil
        previewImage = nil
        recognizedLines = []
        result = nil
        selectedAmountID = nil
    }

    nonisolated private static func previewData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 800,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        guard let output = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
