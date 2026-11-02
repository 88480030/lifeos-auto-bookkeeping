import Compression
import CryptoKit
import Foundation

struct AIChatLine: Identifiable, Codable, Sendable {
    let id: UUID
    let role: AIServiceMessage.Role
    let text: String
    let createdAt: Date
    let attachmentLabel: String?
    let deletion: AIRecordDeletionRequest?
    let proposal: AIPlanProposal?
    let topicUndoID: UUID?

    init(role: AIServiceMessage.Role, text: String, attachmentLabel: String? = nil, proposal: AIPlanProposal? = nil, deletion: AIRecordDeletionRequest? = nil, topicUndoID: UUID? = nil) {
        id = UUID()
        self.role = role
        self.text = text
        self.attachmentLabel = attachmentLabel
        self.proposal = proposal
        self.deletion = deletion
        self.topicUndoID = topicUndoID
        createdAt = .now
    }

    var memoryMessage: AIServiceMessage {
        .init(role: role, content: "[\(createdAt.formatted(.iso8601))] " + text)
    }
}

/// Durable local memory, not an evictable system cache. Original messages are
/// encoded once and losslessly compressed; the search index only refers to them.
enum AIChatHistory {
    private struct Archive: Codable {
        let version: Int
        let lines: [AIChatLine]
    }
    struct StorageInfo: Sendable {
        let messages: Int
        let bytes: Int
        let originalBytes: Int
    }
    private static let magic = Data("LOSMEM02".utf8)
    private static let maximumBytes = 64 * 1024 * 1024
    private static let lock = NSLock()

    static func directory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }
    static func url(in directory: URL? = nil) throws -> URL {
        try (directory ?? Self.directory()).appendingPathComponent("lifeos-ai-memory-v2.bin")
    }
    private static func legacyURL(in directory: URL? = nil) throws -> URL {
        try (directory ?? Self.directory()).appendingPathComponent("lifeos-ai-conversation-v1.json")
    }

    static func load(in directory: URL? = nil) throws -> [AIChatLine] {
        lock.lock(); defer { lock.unlock() }
        let file = try url(in: directory)
        if FileManager.default.fileExists(atPath: file.path) {
            return try decode(Data(contentsOf: file))
        }
        let legacy = try legacyURL(in: directory)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return [] }
        // Do not silently fall back to stale legacy data if the new archive is damaged.
        let lines = try JSONDecoder().decode([AIChatLine].self, from: Data(contentsOf: legacy))
        // Keep the original file untouched as a migration fallback, never as a live copy.
        try encoded(lines).write(to: file, options: [.atomic, .completeFileProtection])
        return lines
    }

    static func save(_ lines: [AIChatLine], in directory: URL? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        try encoded(lines).write(to: url(in: directory), options: [.atomic, .completeFileProtection])
        // Explicit in-app clear must also clear the one-time migration fallback.
        let legacy = try legacyURL(in: directory)
        if lines.isEmpty, FileManager.default.fileExists(atPath: legacy.path) {
            try Data("[]".utf8).write(to: legacy, options: [.atomic, .completeFileProtection])
        }
    }

    static func loadAsync() async throws -> [AIChatLine] {
        try await Task.detached(priority: .userInitiated) { try load() }.value
    }
    static func saveAsync(_ lines: [AIChatLine]) async throws {
        try await Task.detached(priority: .utility) { try save(lines) }.value
    }

    static func info(in directory: URL? = nil) throws -> StorageInfo {
        lock.lock(); defer { lock.unlock() }
        let data = try Data(contentsOf: url(in: directory))
        let lines = try decode(data)
        return StorageInfo(messages: lines.count, bytes: data.count, originalBytes: originalSize(data))
    }

    private static func encoded(_ lines: [AIChatLine]) throws -> Data {
        let raw = try JSONEncoder().encode(Archive(version: 2, lines: lines))
        guard raw.count <= maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        var compressed = Data(count: raw.count + 1024)
        let count = compressed.withUnsafeMutableBytes { output in
            raw.withUnsafeBytes { input in
                compression_encode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, output.count,
                    input.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_LZFSE)
            }
        }
        let useCompression = count > 0 && count < raw.count
        var result = magic
        result.append(useCompression ? 1 : 0)
        var length = UInt64(raw.count).littleEndian
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        result.append(contentsOf: SHA256.hash(data: raw))
        result.append(useCompression ? compressed.prefix(count) : raw)
        return result
    }

    private static func originalSize(_ data: Data) -> Int {
        guard data.count >= 17 else { return 0 }
        let length = data[9..<17].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * $1.offset) }
        return length <= UInt64(maximumBytes) ? Int(length) : 0
    }

    private static func decode(_ data: Data) throws -> [AIChatLine] {
        guard data.count >= 49, data.prefix(8) == magic, data[8] <= 1 else { throw CocoaError(.fileReadCorruptFile) }
        let length = originalSize(data)
        guard length > 0, data.count <= maximumBytes + 49 else { throw CocoaError(.fileReadCorruptFile) }
        let payload = Data(data.dropFirst(49))
        guard !payload.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let raw: Data
        if data[8] == 0 {
            guard payload.count == length else { throw CocoaError(.fileReadCorruptFile) }
            raw = payload
        } else {
            var output = Data(count: length)
            let count = output.withUnsafeMutableBytes { destination in
                payload.withUnsafeBytes { source in
                    compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, destination.count,
                        source.bindMemory(to: UInt8.self).baseAddress!, source.count, nil, COMPRESSION_LZFSE)
                }
            }
            guard count == length else { throw CocoaError(.fileReadCorruptFile) }
            raw = output
        }
        guard Data(SHA256.hash(data: raw)) == data[17..<49] else { throw CocoaError(.fileReadCorruptFile) }
        let archive = try JSONDecoder().decode(Archive.self, from: raw)
        guard archive.version == 2 else { throw CocoaError(.fileReadUnknownStringEncoding) }
        return archive.lines
    }

    static func profileURL() throws -> URL { try directory().appendingPathComponent("lifeos-ai-profile-v1.txt") }
    static func loadProfile() throws -> String {
        let file = try profileURL()
        guard FileManager.default.fileExists(atPath: file.path) else { return "" }
        return try String(contentsOf: file, encoding: .utf8)
    }
    static func saveProfile(_ text: String) throws {
        try Data(text.utf8).write(to: profileURL(), options: [.atomic, .completeFileProtection])
    }
}
