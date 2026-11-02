import Foundation

/// 识别结果只预填编辑器，不是已经保存的交易；不持有原截图。
struct ReceiptEditorDraft: Identifiable {
    let id = UUID()
    let result: ReceiptParseResult
    let selectedAmount: ReceiptAmountCandidate?
}
