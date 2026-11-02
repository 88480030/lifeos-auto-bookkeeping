import Foundation
import ImageIO
import Vision

enum ReceiptRecognitionError: LocalizedError, Sendable {
    case invalidImage
    case imageTooLarge
    case noText
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "这张图片无法读取，请重新选择付款截图。"
        case .imageTooLarge:
            "图片过大，请裁剪到付款信息区域或压缩后重试。"
        case .noText:
            "没有识别到文字，请选择清晰、完整的付款截图。"
        case .recognitionFailed:
            "图片文字暂未识别成功，请换一张清晰截图重试。"
        }
    }
}

/// 本机 Vision 识别。图片和识别文本不写入磁盘，也不发送到网络。
enum ReceiptTextRecognizer {
    static let maximumFileBytes = 25 * 1_024 * 1_024
    private static let maximumPixelCount = 80_000_000.0
    private static let thumbnailMaximumSide = 2_400

    static func recognize(imageData: Data) async throws -> [String] {
        try Task.checkCancellation()
        guard !imageData.isEmpty else { throw ReceiptRecognitionError.invalidImage }
        guard imageData.count <= maximumFileBytes else { throw ReceiptRecognitionError.imageTooLarge }

        let cancellation = ReceiptRecognitionCancellation()
        return try await withTaskCancellationHandler {
            let worker = Task.detached(priority: .userInitiated) {
                try autoreleasepool {
                    try recognizeSynchronously(imageData: imageData, cancellation: cancellation)
                }
            }
            let lines = try await worker.value
            try Task.checkCancellation()
            return lines
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func recognizeSynchronously(
        imageData: Data,
        cancellation: ReceiptRecognitionCancellation
    ) throws -> [String] {
        try cancellation.check()
        guard let source = CGImageSourceCreateWithData(
            imageData as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw ReceiptRecognitionError.invalidImage
        }

        let pixelWidth = width.doubleValue
        let pixelHeight = height.doubleValue
        guard pixelWidth > 0, pixelHeight > 0 else { throw ReceiptRecognitionError.invalidImage }
        guard pixelWidth * pixelHeight <= maximumPixelCount else {
            throw ReceiptRecognitionError.imageTooLarge
        }

        // ImageIO 应用 EXIF 方向并在解码时缩图，避免整张大图进入 UIKit 主线程。
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaximumSide,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ReceiptRecognitionError.invalidImage
        }
        try cancellation.check()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        request.customWords = ["微信支付", "支付宝", "付款成功", "支付成功", "实付", "实际付款", "收款方", "交易时间", "交易单号"]
        request.progressHandler = { request, _, _ in
            if cancellation.isCancelled { request.cancel() }
        }

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            try cancellation.check()
            throw ReceiptRecognitionError.recognitionFailed
        }
        try cancellation.check()

        let fragments = (request.results ?? []).compactMap { observation -> ReceiptTextFragment? in
            guard let text = observation.topCandidates(1).first?.string
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return ReceiptTextFragment(text: text, bounds: observation.boundingBox)
        }
        let lines = readingLines(fragments)
        guard !lines.isEmpty else { throw ReceiptRecognitionError.noText }
        return lines
    }

    /// Vision 可能把同一行的左侧标签与右侧值分为多个 observation。
    /// 先按垂直位置分行，再按横向位置连接，保留账单标签和值的对应关系。
    private static func readingLines(_ fragments: [ReceiptTextFragment]) -> [String] {
        let topToBottom = fragments.sorted {
            if $0.bounds.midY == $1.bounds.midY { return $0.bounds.minX < $1.bounds.minX }
            return $0.bounds.midY > $1.bounds.midY
        }
        var rows: [[ReceiptTextFragment]] = []
        for fragment in topToBottom {
            if let anchor = rows.last?.first,
               abs(anchor.bounds.midY - fragment.bounds.midY) <= max(0.004, min(anchor.bounds.height, fragment.bounds.height) * 0.6) {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in
            row.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.text).joined(separator: " ")
        }
    }
}

private struct ReceiptTextFragment {
    let text: String
    let bounds: CGRect
}

/// 跨工作线程仅共享一个受锁保护的取消标记，不跨线程传递 Vision 请求。
private final class ReceiptRecognitionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    func check() throws {
        if isCancelled { throw CancellationError() }
    }
}
