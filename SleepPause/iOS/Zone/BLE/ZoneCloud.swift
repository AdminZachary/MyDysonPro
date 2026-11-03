// Adapted from nikships/dyson-zone-companion (MIT License, Copyright (c) 2026 Nik).
// Talks to the Dyson cloud ONCE, on this iPhone, to fetch YOUR Zone's long-term BLE key.
import Foundation
import Security

struct ZoneCredentials: Codable, Equatable {
    var email: String
    var accountId: String
    var serial: String
    var ltk: String
}

struct ZoneCloudDevice: Decodable, Identifiable {
    var id: String { serialNumber ?? UUID().uuidString }
    let serialNumber: String?
    let name: String?
    let category: String?
    let model: String?
    let type: String?
    var looksLikeZone: Bool {
        type == "571" || (name ?? "").localizedCaseInsensitiveContains("zone") || (model ?? "").uppercased().hasPrefix("WP01")
    }
}

enum ZoneCloudError: LocalizedError {
    case http(Int, String), message(String)
    var errorDescription: String? {
        switch self {
        case .http(let c, let b): return "Dyson 返回 \(c)：\(b.prefix(200))"
        case .message(let m): return m
        }
    }
}

struct ZoneCloud {
    /// Default host used by dyson-zone-companion. China-region accounts may need a different host
    /// (UNVERIFIED) — the login screen lets you edit it.
    static let defaultHost = "appapi.cp.dyson.com"
    let host: URL
    let country: String
    let culture: String

    init(host: String = ZoneCloud.defaultHost, country: String = Locale.current.region?.identifier ?? "US") {
        self.host = URL(string: "https://\(host)")!
        self.country = country
        culture = "en-\(country)"
    }

    func beginLogin(email: String) async throws -> String {
        _ = try await request("GET", "/v1/provisioningservice/application/Android/version")
        _ = try await request("POST", "/v3/userregistration/email/userstatus", query: ["country": country], body: ["email": email])
        let data = try await request("POST", "/v3/userregistration/email/auth", query: ["country": country, "culture": culture], body: ["email": email])
        guard let c = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["challengeId"] as? String else {
            throw ZoneCloudError.message("Dyson 没有返回验证码挑战，这个邮箱注册过 MyDyson 吗？")
        }
        return c
    }

    func completeLogin(email: String, password: String, challengeId: String, code: String) async throws -> (token: String, accountId: String) {
        let data = try await request("POST", "/v3/userregistration/email/verify", query: ["country": country, "culture": culture],
                                     body: ["challengeId": challengeId, "email": email, "otpCode": code, "password": password])
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = j["token"] as? String, let account = j["account"] as? String else {
            throw ZoneCloudError.message("登录成功但没有拿到 token")
        }
        return (token, account)
    }

    func devices(token: String) async throws -> [ZoneCloudDevice] {
        for path in ["/v3/manifest", "/v2/provisioningservice/manifest"] {
            if let data = try? await request("GET", path, headers: ["Authorization": "Bearer \(token)"]),
               let list = try? JSONDecoder().decode([ZoneCloudDevice].self, from: data) {
                return list
            }
        }
        throw ZoneCloudError.message("读取设备列表失败")
    }

    func ltk(serial: String, token: String) async throws -> String {
        let escaped = serial.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? serial
        let data = try await request("GET", "/v1/lec/\(escaped)/ltk",
                                     headers: ["Authorization": "Bearer \(token)", "X-Dyson-ApiAuthCode": "80541406"])
        guard let ltk = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["ltk"] as? String else {
            throw ZoneCloudError.message("没有拿到 \(serial) 的密钥")
        }
        return ltk
    }

    private func request(_ method: String, _ path: String, query: [String: String] = [:],
                         body: [String: String]? = nil, headers: [String: String] = [:]) async throws -> Data {
        var comps = URLComponents(url: host.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue("android client", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ZoneCloudError.http(code, String(data: data, encoding: .utf8) ?? "") }
        return data
    }
}

/// Stores the Zone key in the iOS Keychain (this device only, readable after first unlock so
/// background reconnects work). Password is never stored.
enum ZoneKeychain {
    private static let service = "SleepPause.DysonZone"
    private static let account = "credentials"

    static func save(_ c: ZoneCredentials) throws {
        let data = try JSONEncoder().encode(c)
        delete()
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ZoneCloudError.message("Keychain 保存失败（\(status)）")
        }
    }

    static func load() -> ZoneCredentials? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(ZoneCredentials.self, from: data)
    }

    static func delete() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}
