import CryptoKit
import Foundation
import OctoPrintKit
import Security

/// A configured OctoPrint server. The API key lives in `CredentialStore`, not here.
struct Instance: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var baseURL: URL
    /// Multiplier on OctoPrint's 0.5s push interval. Raise for slow links.
    var pushThrottle = 1
    /// Identity colour for this printer ("filament colour"), e.g. `#8F7CFF`.
    var filamentHex: String?
    /// SHA-256 fingerprint of a self-signed HTTPS certificate you chose to trust for this printer.
    var trustedCertificate: String?

    /// Normalises user input like `octoprint1.local` or `https://host/octoprint` into a base URL.
    static func normalisedURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard var components = URLComponents(string: text), components.host?.isEmpty == false else { return nil }
        if !components.path.hasSuffix("/") { components.path += "/" }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

/// How OctoMac gets past a reverse proxy in front of OctoPrint: a user name and password (HTTP basic
/// authentication) and/or extra headers, such as Cloudflare Access service tokens. Kept with the API key, never in
/// the printer list.
struct ProxyAccess: Codable, Equatable, Sendable {
    struct Header: Codable, Equatable, Identifiable, Sendable {
        var id = UUID()
        var name = ""
        var value = ""
    }

    var user = ""
    var password = ""
    var headers: [Header] = []

    var isEmpty: Bool { user.isEmpty && password.isEmpty && httpHeaders.isEmpty }

    /// The headers to send with every request to the printer.
    var httpHeaders: [String: String] {
        var result: [String: String] = [:]
        for header in headers {
            let name = header.name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { result[name] = header.value.trimmingCharacters(in: .whitespaces) }
        }
        if !user.isEmpty || !password.isEmpty {
            result["Authorization"] = OctoPrintClient.basicAuthorization(user: user, password: password)
        }
        return result
    }
}

/// API keys, and any proxy sign-in (`ProxyAccess`). Kept in the macOS Keychain by default (see `keychainByDefault`).
/// Settings can switch to `~/Library/Application Support/OctoMac/api-keys.dat` instead: JSON sealed with AES-GCM under a
/// key compiled into the app, with owner-only (0600) permissions. That keeps keys out of plain text (backups, grep,
/// screenshots) but isn't protection against someone who has the app binary, since the app is open source.
enum CredentialStore {
    static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "OctoMac/api-keys.dat")
    }()

    static let useKeychainKey = "credentials.useKeychain"
    /// Where secrets are kept right now. Settled once at launch by `settleStorage`, then changed only from Settings.
    static var usesKeychain: Bool { UserDefaults.standard.bool(forKey: useKeychainKey) }

    /// The Keychain is the default for builds signed with a Developer ID, such as releases: their signature stays the
    /// same across updates, so the Keychain never asks for permission again. Builds signed ad-hoc (a contributor's own)
    /// look like a new app after every rebuild and would be asked each time, so they keep the file.
    static var keychainByDefault: Bool {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any]
        else { return false }
        return information[kSecCodeInfoTeamIdentifier as String] != nil
    }

    /// On first launch (or the first launch of a version with this choice), uses the default storage and moves any
    /// keys already saved into it. A choice made in Settings is never changed.
    static func settleStorage(ids: [UUID]) {
        guard UserDefaults.standard.object(forKey: useKeychainKey) == nil else { return }
        UserDefaults.standard.set(false, forKey: useKeychainKey)
        if keychainByDefault, !setUsesKeychain(true, ids: ids) {
            // The Keychain wouldn't take the keys; they stay in the file, which still works.
            UserDefaults.standard.set(false, forKey: useKeychainKey)
        }
    }

    private static let sealingKey = SymmetricKey(data: SHA256.hash(data: Data("uk.co.district5.OctoMac/credentials/v1/7c1e9a4b".utf8)))

    static func apiKey(for id: UUID) -> String? { secret(id.uuidString) }

    static func setAPIKey(_ key: String?, for id: UUID) { setSecret(key, id.uuidString) }

    static func proxyAccess(for id: UUID) -> ProxyAccess? {
        secret(accessAccount(id)).flatMap { try? JSONDecoder().decode(ProxyAccess.self, from: Data($0.utf8)) }
    }

    static func setProxyAccess(_ access: ProxyAccess?, for id: UUID) {
        let json = access.flatMap { $0.isEmpty ? nil : try? JSONEncoder().encode($0) }
        setSecret(json.map { String(decoding: $0, as: UTF8.self) }, accessAccount(id))
    }

    /// Forgets everything stored for a printer.
    static func remove(_ id: UUID) {
        setAPIKey(nil, for: id)
        setProxyAccess(nil, for: id)
    }

    private static func accessAccount(_ id: UUID) -> String { id.uuidString + ".access" }
    private static func accounts(_ ids: [UUID]) -> [String] { ids.flatMap { [$0.uuidString, accessAccount($0)] } }

    private static func secret(_ account: String) -> String? {
        usesKeychain ? Keychain.secret(account) : load()[account]
    }

    private static func setSecret(_ value: String?, _ account: String) {
        let value = (value?.isEmpty ?? true) ? nil : value
        if usesKeychain {
            if let value { Keychain.set(value, account) } else { Keychain.delete(account) }
        } else {
            var keys = load()
            keys[account] = value
            save(keys)
        }
    }

    /// Moves every key to the Keychain or back to the file, then switches over. Returns false (and changes nothing)
    /// if a key couldn't be written.
    @discardableResult
    static func setUsesKeychain(_ on: Bool, ids: [UUID]) -> Bool {
        guard on != usesKeychain else { return true }
        if on {
            let keys = load()
            for account in accounts(ids) {
                guard let key = keys[account] else { continue }
                guard Keychain.set(key, account) else { return false }
            }
            UserDefaults.standard.set(true, forKey: useKeychainKey)
            save([:])
            try? FileManager.default.removeItem(at: fileURL)
        } else {
            var keys: [String: String] = [:]
            for account in accounts(ids) { if let key = Keychain.secret(account) { keys[account] = key } }
            save(keys)
            UserDefaults.standard.set(false, forKey: useKeychainKey)
            accounts(ids).forEach(Keychain.delete)
        }
        return true
    }

    private static func load() -> [String: String] {
        if let sealed = try? Data(contentsOf: fileURL),
           let box = try? AES.GCM.SealedBox(combined: sealed),
           let json = try? AES.GCM.open(box, using: sealingKey)
        {
            return (try? JSONDecoder().decode([String: String].self, from: json)) ?? [:]
        }
        return [:]
    }

    private static func save(_ keys: [String: String]) {
        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let json = try? JSONEncoder().encode(keys),
              let data = try? AES.GCM.seal(json, using: sealingKey).combined
        else { return }
        // Create with 0600 before writing so the file is never world-readable.
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try? data.write(to: fileURL)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

/// API keys in the macOS Keychain, one generic password per printer (and one more for a proxy sign-in).
private enum Keychain {
    private static let service = "uk.co.district5.OctoMac.apikey"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func secret(_ account: String) -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ key: String, _ account: String) -> Bool {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "OctoMac API key"
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
