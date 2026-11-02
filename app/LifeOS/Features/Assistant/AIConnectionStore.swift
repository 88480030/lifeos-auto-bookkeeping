import Combine
import Foundation
import Security

enum AIConnectionError: LocalizedError {
    case invalidEndpoint
    case invalidModel
    case missingAPIKey
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "请输入 HTTPS 接口地址，不要包含账号、密码、查询参数或片段。"
        case .invalidModel:
            "请填写模型名称（最多 120 个字符）。"
        case .missingAPIKey:
            "请先在连接设置中保存 API 密钥。"
        case .keychainFailure:
            "无法访问系统钥匙串，请解锁设备后重试。"
        }
    }
}

struct AIServiceCredentials: Sendable {
    let endpoint: URL
    let model: String
    let apiKey: String
}

@MainActor
final class AIConnectionStore: ObservableObject {
    @Published private(set) var endpoint: String
    @Published private(set) var model: String
    @Published private(set) var hasAPIKey: Bool

    private let defaults: UserDefaults
    private let endpointKey = "lifeos.ai.endpoint.v1"
    private let modelKey = "lifeos.ai.model.v1"
    private let keychainService = "com.example.LifeOS.ai.credentials"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        endpoint = defaults.string(forKey: endpointKey) ?? ""
        model = defaults.string(forKey: modelKey) ?? ""
        hasAPIKey = false
        if let origin = try? Self.origin(from: endpoint) {
            hasAPIKey = (try? readAPIKey(origin: origin)) != nil
        }
    }

    /// A blank key keeps an existing key; deletion requires the explicit clear action.
    func save(endpoint: String, model: String, apiKey: String) throws {
        let cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let origin = try Self.origin(from: cleanEndpoint)
        guard !cleanModel.isEmpty, cleanModel.count <= 120,
              cleanModel.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw AIConnectionError.invalidModel
        }
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanKey.isEmpty {
            guard cleanKey.utf8.count <= 8192,
                  cleanKey.rangeOfCharacter(from: .controlCharacters) == nil else { throw AIServiceError.invalidKey }
            try writeAPIKey(cleanKey, origin: origin)
        }
        defaults.set(cleanEndpoint, forKey: endpointKey)
        defaults.set(cleanModel, forKey: modelKey)
        self.endpoint = cleanEndpoint
        self.model = cleanModel
        hasAPIKey = (try? readAPIKey(origin: origin)) != nil
    }

    func clearAPIKey() throws {
        let origin = try Self.origin(from: endpoint)
        let result = SecItemDelete(keychainQuery(origin: origin) as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else {
            throw AIConnectionError.keychainFailure(result)
        }
        hasAPIKey = false
    }

    func credentials() throws -> AIServiceCredentials {
        let address = try Self.completionsURL(from: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanModel.isEmpty, cleanModel.count <= 120,
              cleanModel.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw AIConnectionError.invalidModel
        }
        let origin = try Self.origin(from: endpoint)
        guard let key = try readAPIKey(origin: origin), !key.isEmpty else { throw AIConnectionError.missingAPIKey }
        return AIServiceCredentials(endpoint: address, model: cleanModel, apiKey: key)
    }

    static func completionsURL(from input: String) throws -> URL {
        guard var components = URLComponents(string: input),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              !input.contains(where: { $0.isNewline || $0.isWhitespace }) else {
            throw AIConnectionError.invalidEndpoint
        }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/chat/completions") { path += "/chat/completions" }
        components.path = path
        guard let url = components.url else { throw AIConnectionError.invalidEndpoint }
        return url
    }

    private static func origin(from input: String) throws -> String {
        let validated = try completionsURL(from: input)
        guard let parts = URLComponents(url: validated, resolvingAgainstBaseURL: false),
              let host = parts.host?.lowercased() else { throw AIConnectionError.invalidEndpoint }
        let authority = host.contains(":") ? "[\(host)]" : host
        let port = parts.port.flatMap { $0 == 443 ? nil : ":\($0)" } ?? ""
        return "https://\(authority)\(port)"
    }

    private func keychainQuery(origin: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: "chat-api-key|\(origin)"]
    }

    private func readAPIKey(origin: String) throws -> String? {
        var query = keychainQuery(origin: origin)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw AIConnectionError.keychainFailure(status)
        }
        return key
    }

    private func writeAPIKey(_ value: String, origin: String) throws {
        let data = Data(value.utf8)
        let query = keychainQuery(origin: origin)
        let update: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            update.forEach { item[$0.key] = $0.value }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AIConnectionError.keychainFailure(status) }
    }
}
