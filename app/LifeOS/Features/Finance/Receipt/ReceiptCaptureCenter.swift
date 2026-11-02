import Combine
import Foundation

struct ReceiptCaptureRequest: Identifiable {
    let id = UUID()
    var imageData: Data? = nil
    var automaticallySave = false
}

/// 截图仅在本次识别流程中持有；接收方取走后清除请求。
@MainActor
final class ReceiptCaptureCenter: ObservableObject {
    static let shared = ReceiptCaptureCenter()
    @Published private(set) var request: ReceiptCaptureRequest?

    func present(imageData: Data? = nil, automaticallySave: Bool = false) {
        request = ReceiptCaptureRequest(imageData: imageData, automaticallySave: automaticallySave)
    }

    func clear() { request = nil }
}
