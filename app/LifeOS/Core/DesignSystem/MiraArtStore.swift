import SwiftUI
import UIKit

/// 本机角色立绘存储：默认使用内置漫画立绘，用户可从相册导入自己的立绘覆盖。
@MainActor
final class MiraArtStore: ObservableObject {
    static let shared = MiraArtStore()

    @Published private(set) var customImage: UIImage?

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = support.appendingPathComponent("LifeOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("MiraArtwork.png")
        if let data = try? Data(contentsOf: fileURL) {
            customImage = UIImage(data: data)
        }
    }

    func importImage(data: Data) throws {
        guard let image = UIImage(data: data) else {
            throw MiraArtworkError.invalidImage
        }
        guard let png = image.pngData() else {
            throw MiraArtworkError.invalidImage
        }
        try png.write(to: fileURL, options: .atomic)
        customImage = UIImage(data: png)
    }

    func reset() {
        try? FileManager.default.removeItem(at: fileURL)
        customImage = nil
    }
}

enum MiraArtworkError: LocalizedError {
    case invalidImage
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "这张图片无法读取，请换一张 JPG / PNG / HEIC 图片。"
        case .saveFailed:
            return "图片保存失败，请重试。"
        }
    }
}
