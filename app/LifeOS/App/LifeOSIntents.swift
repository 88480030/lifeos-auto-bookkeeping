import AppIntents
import UniformTypeIdentifiers

@available(iOS 18.0, *)
struct ReceiptCaptureIntent: AppIntent {
    static var title: LocalizedStringResource { "截图记账" }
    static var description: IntentDescription { IntentDescription("在本机识别付款截图，金额明确时直接记账；同金额不询问，明确重复时跳过。可以从快捷指令传入一张图片。") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "付款截图", supportedContentTypes: [.image])
    var screenshot: IntentFile?

    func perform() async throws -> some IntentResult {
        let data = screenshot?.data
        if let data, data.count > ReceiptTextRecognizer.maximumFileBytes {
            throw ReceiptRecognitionError.imageTooLarge
        }
        await MainActor.run {
            ReceiptCaptureCenter.shared.present(imageData: data, automaticallySave: data != nil)
        }
        return .result()
    }
}

struct QuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource { "一键记账" }
    static var description: IntentDescription { IntentDescription("快速记录一笔支出或收入，打开 LifeOS 的数字键盘。") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "金额", description: "可选，例如 28.5")
    var amount: Double?

    @Parameter(title: "备注", description: "可选，例如 午餐")
    var note: String?

    @Parameter(title: "分类", description: "可选，例如 餐饮")
    var category: String?

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            QuickCaptureCenter.shared.present(amount: amount, note: note, category: category)
        }
        return .result()
    }
}

struct LifeOSAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickCaptureIntent(),
            phrases: [
                "用 \(.applicationName) 记一笔",
                "\(.applicationName) 一键记账"
            ],
            shortTitle: "一键记账",
            systemImageName: "plus.circle.fill"
        )
    }
}
