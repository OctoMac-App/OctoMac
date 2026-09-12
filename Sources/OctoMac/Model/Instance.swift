import CryptoKit
import Foundation
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

/// API keys. By default they're stored in `~/Library/Application Support/OctoMac/api-keys.dat`: JSON sealed with
/// AES-GCM under a key compiled into the app, with owner-only (0600) permissions. This keeps keys out of plain text
/// (backups, grep, screenshots) but isn't protection against someone who has the app binary, an accepted trade-off
/// for printer API keys. Settings can switch to the macOS Keychain instead (off by default: builds that aren't
/// Developer ID signed get a Keychain prompt after every rebuild).
enum CredentialStore {
    static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "OctoMac/api-keys.dat")
    }()

    static let useKeychainKey = "credentials.useKeychain"
    static var usesKeychain: Bool { UserDefaults.standard.bool(forKey: useKeychainKey) }

    /// Plain-JSON file written by an earlier build; migrated and removed on first load.
    private static let legacyPlainURL = fileURL.deletingLastPathComponent().appending(path: "api-keys.json")

    private static let sealingKey = SymmetricKey(data: SHA256.hash(data: Data("uk.co.district5.OctoMac/credentials/v1/7c1e9a4b".utf8)))

    static func apiKey(for id: UUID) -> String? {
        usesKeychain ? Keychain.apiKey(for: id) : load()[id.uuidString]
    }

    static func setAPIKey(_ key: String?, for id: UUID) {
        let key = (key?.isEmpty ?? true) ? nil : key
        if usesKeychain {
            if let key { Keychain.set(key, for: id) } else { Keychain.delete(id) }
        } else {
            var keys = load()
            keys[id.uuidString] = key
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
            for id in ids {
                guard let key = keys[id.uuidString] else { continue }
                guard Keychain.set(key, for: id) else { return false }
            }
            UserDefaults.standard.set(true, forKey: useKeychainKey)
            save([:])
            try? FileManager.default.removeItem(at: fileURL)
        } else {
            var keys: [String: String] = [:]
            for id in ids { if let key = Keychain.apiKey(for: id) { keys[id.uuidString] = key } }
            save(keys)
            UserDefaults.standard.set(false, forKey: useKeychainKey)
            ids.forEach(Keychain.delete)
        }
        return true
    }

    /// One-time move of keys saved by early builds from the Keychain into the file.
    static func migrateFromKeychain(ids: [UUID]) {
        let flag = "credentials.migratedFromKeychain"
        guard !UserDefaults.standard.bool(forKey: flag), !usesKeychain else { return }
        var keys = load()
        for id in ids where keys[id.uuidString] == nil {
            if let key = Keychain.apiKey(for: id) { keys[id.uuidString] = key }
        }
        save(keys)
        ids.forEach(Keychain.delete)
        UserDefaults.standard.set(true, forKey: flag)
    }

    private static func load() -> [String: String] {
        if let sealed = try? Data(contentsOf: fileURL),
           let box = try? AES.GCM.SealedBox(combined: sealed),
           let json = try? AES.GCM.open(box, using: sealingKey)
        {
            return (try? JSONDecoder().decode([String: String].self, from: json)) ?? [:]
        }
        if let plain = try? Data(contentsOf: legacyPlainURL),
           let keys = try? JSONDecoder().decode([String: String].self, from: plain)
        {
            save(keys)
            try? FileManager.default.removeItem(at: legacyPlainURL)
            return keys
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

/// API keys in the macOS Keychain, one generic password per printer.
private enum Keychain {
    private static let service = "uk.co.district5.OctoMac.apikey"

    private static func query(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }

    static func apiKey(for id: UUID) -> String? {
        var request = query(id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ key: String, for id: UUID) -> Bool {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query(id)
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "OctoMac API key"
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ id: UUID) {
        SecItemDelete(query(id) as CFDictionary)
    }
}
