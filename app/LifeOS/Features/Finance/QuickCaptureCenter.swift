import SwiftUI

struct QuickCaptureRequest: Identifiable, Equatable {
    let id = UUID()
    var amount: Double?
    var note: String?
    var categoryName: String?
}

@MainActor
final class QuickCaptureCenter: ObservableObject {
    static let shared = QuickCaptureCenter()

    @Published var request: QuickCaptureRequest?

    private init() {}

    func present(amount: Double? = nil, note: String? = nil, category: String? = nil) {
        request = QuickCaptureRequest(amount: amount, note: note, categoryName: category)
    }

    func clear() {
        request = nil
    }
}
