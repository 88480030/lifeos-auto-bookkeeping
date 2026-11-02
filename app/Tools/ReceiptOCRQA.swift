// Compile together with ReceiptTextRecognizer.swift on macOS. No app database is opened.
import AppKit
import Foundation
import ImageIO
import Vision

@main
struct ReceiptOCRQA {
    @MainActor
    static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/verification/receipt-capture", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let receipt = makeImage(lines: [
            "测试样张 · 不是真实交易", "微信支付", "支付成功", "星河咖啡",
            "实付金额 ￥28.50", "原价 ￥35.00", "优惠 ￥6.50", "收款方 星河咖啡",
            "交易时间 2026-10-27 12:05:00", "支付方式 微信支付",
            "交易单号 4200000000202610270000000285"
        ])
        let blank = makeImage(lines: [])
        let fixtureURL = output.appendingPathComponent("receipt-wechat-synthetic.png")
        try receipt.write(to: fixtureURL)
        try blank.write(to: output.appendingPathComponent("receipt-blank-synthetic.png"))

        var checks: [String: String] = [:]
        do {
            _ = try await ReceiptTextRecognizer.recognize(imageData: Data("not an image".utf8))
            checks["invalidImage"] = "failed: invalid image accepted"
        } catch ReceiptRecognitionError.invalidImage {
            checks["invalidImage"] = "passed"
        } catch { checks["invalidImage"] = "failed: \(error)" }

        do {
            _ = try await ReceiptTextRecognizer.recognize(imageData: Data(repeating: 0, count: ReceiptTextRecognizer.maximumFileBytes + 1))
            checks["oversizedImage"] = "failed: oversized image accepted"
        } catch ReceiptRecognitionError.imageTooLarge {
            checks["oversizedImage"] = "passed"
        } catch { checks["oversizedImage"] = "failed: \(error)" }

        let cancelled = Task { try await ReceiptTextRecognizer.recognize(imageData: receipt) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            checks["preCancelledTask"] = "failed: cancellation ignored"
        } catch is CancellationError {
            checks["preCancelledTask"] = "passed"
        } catch { checks["preCancelledTask"] = "failed: \(error)" }

        var receiptLines: [String] = []
        var diagnostic: String?
        do {
            receiptLines = try await ReceiptTextRecognizer.recognize(imageData: receipt)
            let text = receiptLines.joined(separator: "\n")
            let expected = ["28.50", "35.00", "6.50", "星河咖啡", "2026-10-27", "12:05"]
            let missing = expected.filter { !text.contains($0) }
            checks["receiptOCR"] = missing.isEmpty ? "passed" : "failed: missing \(missing.joined(separator: ", "))"
        } catch {
            checks["receiptOCR"] = "blocked: \(error.localizedDescription)"
            diagnostic = await visionDiagnostic(imageData: receipt)
        }

        do {
            _ = try await ReceiptTextRecognizer.recognize(imageData: blank)
            checks["blankImage"] = "failed: blank image returned text"
        } catch ReceiptRecognitionError.noText {
            checks["blankImage"] = "passed"
        } catch { checks["blankImage"] = "blocked: \(error.localizedDescription)" }

        let passed = checks.values.allSatisfy { $0 == "passed" }
        let report: [String: Any] = [
            "status": passed ? "passed" : "incomplete",
            "fixture": fixtureURL.path,
            "fixtureType": "synthetic text screenshot, not a real payment",
            "checks": checks,
            "recognizedLines": receiptLines,
            "visionDiagnostic": diagnostic ?? "not needed",
            "databaseWrites": false,
            "networkUploads": false
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: output.appendingPathComponent("ocr-qa-result.json"))
        print(String(decoding: data, as: UTF8.self))
        if !passed { exit(1) }
    }

    @MainActor
    private static func makeImage(lines: [String]) -> Data {
        let width = 1_290
        let height = 2_100
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        let font = NSFont(name: "PingFang SC", size: 40) ?? .systemFont(ofSize: 40)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        for (index, line) in lines.enumerated() {
            line.draw(at: NSPoint(x: 70, y: 1_960 - index * 160), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }

    /// Framework-only diagnostic on the same synthetic fixture, used only after a failed service run.
    private static func visionDiagnostic(imageData: Data) async -> String {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return "ImageIO fixture decode failed" }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.automaticallyDetectsLanguage = true
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
                return "Framework probe succeeded; service error requires investigation"
            } catch {
                let error = error as NSError
                return "\(error.domain) code \(error.code): \(error.localizedDescription)"
            }
        }.value
    }
}
