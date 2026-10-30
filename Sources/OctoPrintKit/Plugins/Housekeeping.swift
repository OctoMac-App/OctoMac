import Foundation

/// OctoPrint's bundled File Check plugin: looks through uploaded G-code for known problems, such as a slicer
/// placeholder that was never filled in, or an OctoPrint API key the slicer wrote into the file. Results are kept per
/// file; the plugin pushes `{"action": "notify", ...}` when it finds something and `{"action": "check_update"}` when
/// results change.
public enum FileCheck {
    public static let pluginID = "file_check"

    public enum Message: Sendable, Equatable {
        case found(storage: String, path: String, problems: [String])
        case updated

        public init?(_ data: JSONValue) {
            switch data["action"]?.stringValue {
            case "notify":
                self = .found(storage: data["storage"]?.stringValue ?? "local", path: data["path"]?.stringValue ?? "",
                              problems: (data["types"]?.arrayValue ?? []).compactMap(\.stringValue))
            case "check_update":
                self = .updated
            default:
                return nil
            }
        }
    }

    /// Problems found, keyed by file path on the Raspberry Pi. Only files on the Pi are checked.
    static func results(_ json: JSONValue) -> [String: [String]] {
        var results: [String: [String]] = [:]
        for (key, value) in json["check_result"]?.objectValue ?? [:] {
            // Keys are "local:folder/file.gcode".
            guard key.hasPrefix("local:") else { continue }
            let problems = (value.arrayValue ?? []).compactMap(\.stringValue)
            if !problems.isEmpty { results[String(key.dropFirst("local:".count))] = problems }
        }
        return results
    }

    /// OctoPrint's page about a problem, such as https://faq.octoprint.org/file-check-travel-speed.
    public static func helpURL(for problem: String) -> URL? {
        URL(string: "https://faq.octoprint.org/file-check-\(problem.replacingOccurrences(of: "_", with: "-"))")
    }
}

/// OctoPrint's logging setup (bundled Logging plugin): how much each part of OctoPrint writes to its log, and whether
/// the serial conversation with the printer is logged.
public struct LoggingSetup: Sendable, Equatable {
    /// Every logger that can be changed, such as "octoprint.server" or "octoprint.plugins.backup".
    public var available: [String]
    /// The loggers set to something other than normal, and their level ("DEBUG", "INFO", "WARNING", "ERROR").
    public var levels: [String: String]
    public var serialLog: Bool

    public init(available: [String], levels: [String: String], serialLog: Bool) {
        self.available = available
        self.levels = levels
        self.serialLog = serialLog
    }

    init(_ json: JSONValue) {
        available = (json.value(at: "setup", "loggers")?.arrayValue ?? []).compactMap(\.stringValue).sorted()
        levels = (json.value(at: "setup", "levels")?.objectValue ?? [:]).compactMapValues(\.stringValue)
        serialLog = json.value(at: "serial_log", "enabled")?.boolValue ?? false
    }
}

/// What an uninstalled plugin left behind: its settings, its data folder, or an entry in the list of switched-off
/// plugins.
public struct PluginLeftovers: Sendable, Hashable, Identifiable {
    public var key: String
    public var settings: Bool
    public var data: Bool
    public var id: String { key }

    public init(key: String, settings: Bool, data: Bool) {
        self.key = key
        self.settings = settings
        self.data = data
    }

    static func list(_ json: JSONValue) -> [PluginLeftovers] {
        (json["orphan_data"]?.objectValue ?? [:]).map { key, value in
            PluginLeftovers(key: key, settings: value["settings"]?.boolValue ?? false, data: value["data"]?.boolValue ?? false)
        }
        .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }
}

/// What OctoPrint found when it fetched an address itself (`/api/util/test`).
public struct AddressCheck: Sendable, Equatable {
    public var ok: Bool
    public var status: Int
    public var contentType: String?
    /// The response itself, when asked for (a camera snapshot, for instance).
    public var content: Data?

    public init(ok: Bool, status: Int, contentType: String? = nil, content: Data? = nil) {
        self.ok = ok
        self.status = status
        self.contentType = contentType
        self.content = content
    }

    init(_ json: JSONValue) {
        ok = json["result"]?.boolValue ?? false
        status = json["status"]?.intValue ?? 0
        contentType = json.value(at: "response", "assumed_content_type")?.stringValue
        content = json.value(at: "response", "content")?.stringValue.flatMap { Data(base64Encoded: $0) }
    }
}

extension OctoPrintClient {
    public func fileCheckResults() async throws -> [String: [String]] {
        FileCheck.results(try await pluginGet(FileCheck.pluginID))
    }

    public func loggingSetup() async throws -> LoggingSetup {
        LoggingSetup(try await get("plugin/logging/"))
    }

    /// Replaces the logging levels: loggers left out go back to normal.
    public func setLoggingLevels(_ levels: [String: String]) async throws {
        let _: JSONValue = try await put("plugin/logging/setup/levels", body: JSONValue.object(levels.mapValues { .string($0) }))
    }

    public func pluginLeftovers() async throws -> [PluginLeftovers] {
        PluginLeftovers.list(try await get("plugin/\(Self.pluginManagerID)/orphans", query: [URLQueryItem(name: "refresh", value: "true")]))
    }

    /// Removes what an uninstalled plugin left behind. Takes effect once OctoPrint restarts.
    public func cleanUpPlugin(_ key: String) async throws {
        _ = try await pluginCommand(Self.pluginManagerID, "cleanup", parameters: ["plugin": .string(key)])
    }

    public func cleanUpAllPlugins() async throws {
        _ = try await pluginCommand(Self.pluginManagerID, "cleanup_all")
    }

    /// Makes a new global API key, replacing any old one, and returns it.
    public func makeGlobalAPIKey() async throws -> String? {
        try await regenerateSystemAPIKey()["apikey"]?.stringValue
    }

    /// Removes the global API key. Application keys, like OctoMac's own, keep working.
    public func removeGlobalAPIKey() async throws {
        try await delete("api/settings/apikey")
    }

    /// Asks OctoPrint to fetch a picture from an address itself, as the Raspberry Pi sees it, and send it back.
    public func checkSnapshot(_ url: String) async throws -> AddressCheck {
        AddressCheck(try await test([
            "command": "url", "url": .string(url), "method": "GET", "timeout": 6,
            "content_type_whitelist": ["image/*"], "response": "bytes",
        ]))
    }
}
