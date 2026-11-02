import AVFoundation
import CoreTransferable
import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// Data is transient and remains on this device until the user sends the message.
struct AIAttachment: Sendable {
    let name: String
    let detail: String
    let extractedText: String
    let imageDataURLs: [String]
}

enum AIAttachmentError: LocalizedError {
    case unsupported, tooLarge, unreadable, emptyDocument, tooLong, videoUnavailable
    var errorDescription: String? {
        switch self {
        case .unsupported: "暂支持图片、PDF、文本文件和视频；其他格式请先转成 PDF 或文本。"
        case .tooLarge: "文件太大，请选择较小的文件（视频不超过 100 MB，其他文件不超过 20 MB）。"
        case .unreadable: "无法读取这个文件，请重新选择。"
        case .emptyDocument: "PDF 没有可提取的文字；请将需要的页面截成图片后发送。"
        case .tooLong: "文件文字超过 20000 字，请分成较小的文件发送。"
        case .videoUnavailable: "无法提取视频画面，请选择 10 分钟以内的本地视频。"
        }
    }
}

/// PhotosPicker gives videos a temporary URL; copy it into the app's temporary
/// directory before the provider's access ends, then delete it after processing.
struct AIImportedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            if let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 100 * 1_024 * 1_024 {
                throw AIAttachmentError.tooLarge
            }
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent("lifeos-ai-video-\(UUID().uuidString)")
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: target)
            return AIImportedVideo(url: target)
        }
    }
}

@MainActor
enum AIAttachmentProcessor {
    private static let maxFileBytes = 20 * 1_024 * 1_024
    private static let maxVideoBytes = 100 * 1_024 * 1_024
    private static let maxTextCharacters = 20_000

    static func removeAbandonedVideos() {
        let folder = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("lifeos-ai-video-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func photo(_ data: Data, name: String = "照片", maxJPEGBytes: Int = 1_800_000) throws -> AIAttachment {
        guard data.count <= maxFileBytes else { throw AIAttachmentError.tooLarge }
        let image = try jpegDataURL(data, maxBytes: maxJPEGBytes)
        return AIAttachment(name: name, detail: "图片 · 发送时上传", extractedText: "", imageDataURLs: [image])
    }

    static func file(_ url: URL) async throws -> AIAttachment {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let info = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isRegularFileKey])
        guard info.isRegularFile != false else { throw AIAttachmentError.unreadable }
        let type = info.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        let limit = type.conforms(to: .movie) ? maxVideoBytes : maxFileBytes
        if let size = info.fileSize, size > limit { throw AIAttachmentError.tooLarge }
        if type.conforms(to: .movie) { return try await video(url, name: url.lastPathComponent) }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maxFileBytes else { throw AIAttachmentError.tooLarge }
        if type.conforms(to: .image) { return try photo(data, name: url.lastPathComponent) }
        if type.conforms(to: .pdf) {
            guard let pdf = PDFDocument(data: data), !pdf.isLocked else { throw AIAttachmentError.unreadable }
            var text = ""
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { throw AIAttachmentError.unreadable }
                let part = page.string ?? ""
                // Reject scanned or mixed PDFs instead of silently skipping pages.
                guard !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIAttachmentError.emptyDocument }
                text += "\n[第 \(i + 1) 页]\n" + part
                guard text.count <= maxTextCharacters else { throw AIAttachmentError.tooLong }
            }
            guard !text.isEmpty else { throw AIAttachmentError.emptyDocument }
            return AIAttachment(name: url.lastPathComponent, detail: "PDF · \(pdf.pageCount) 页文字，不含图表", extractedText: "以下为 PDF 提取的文字，不含图片和图表，不要假装已读取那些内容。\n" + text, imageDataURLs: [])
        }
        if type.conforms(to: .plainText) || type.conforms(to: .text) || type.conforms(to: .json) {
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { throw AIAttachmentError.unreadable }
            guard text.count <= maxTextCharacters else { throw AIAttachmentError.tooLong }
            return AIAttachment(name: url.lastPathComponent, detail: "文本 · \(text.count) 字", extractedText: text, imageDataURLs: [])
        }
        throw AIAttachmentError.unsupported
    }

    static func video(_ url: URL, name: String = "视频") async throws -> AIAttachment {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maxVideoBytes else { throw AIAttachmentError.tooLarge }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 600 else { throw AIAttachmentError.videoUnavailable }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        var frames: [String] = []
        var timestamps: [String] = []
        // Six evenly spaced frames. They do not represent the full video or its audio.
        for i in 0..<6 {
            try Task.checkCancellation()
            let time = CMTime(seconds: duration * (Double(i) + 0.5) / 6.0, preferredTimescale: 600)
            let result = try await generator.image(at: time)
            timestamps.append(String(format: "%.1f 秒", result.actualTime.seconds))
            guard let data = UIImage(cgImage: result.image).jpegData(compressionQuality: 0.7) else { throw AIAttachmentError.videoUnavailable }
            frames.append("data:image/jpeg;base64," + data.base64EncodedString())
        }
        return AIAttachment(name: name, detail: "视频 · 6 张画面，无声音", extractedText: "视频约 \(Int(duration)) 秒，以下图片是按时间均匀提取的 6 个画面，时间依次为 \(timestamps.joined(separator: "、"))。没有视频声音，也没有完整视频；请不要假装看过其他片段或听过音频。", imageDataURLs: frames)
    }

    private static func jpegDataURL(_ data: Data, maxBytes: Int) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw AIAttachmentError.unreadable }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw AIAttachmentError.unreadable }
        let image = UIImage(cgImage: cg)
        guard var jpeg = image.jpegData(compressionQuality: 0.75) else { throw AIAttachmentError.unreadable }
        for quality in [0.6, 0.45, 0.3, 0.2] where jpeg.count > maxBytes {
            if let smaller = image.jpegData(compressionQuality: quality) { jpeg = smaller }
        }
        guard jpeg.count <= maxBytes else { throw AIAttachmentError.tooLarge }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}
