import Foundation

/// An installed OctoPrint plugin, as the bundled Plugin Manager reports it.
/// https://docs.octoprint.org/en/main/bundledplugins/pluginmanager.html
public struct InstalledPlugin: Sendable, Hashable, Identifiable {
    public var key: String
    public var name: String
    public var version: String?
    public var author: String?
    public var summary: String?
    public var homepage: URL?
    public var enabled: Bool
    /// Comes with OctoPrint itself.
    public var bundled: Bool
    /// The Plugin Manager can enable, disable or uninstall it.
    public var managable: Bool
    /// Switched on or off, or uninstalled, but OctoPrint needs a restart to finish.
    public var pending: Bool
    /// Turned off by OctoPrint's safe mode.
    public var safeModeVictim: Bool

    public var id: String { key }

    public init(key: String, name: String, version: String? = nil, author: String? = nil, summary: String? = nil, homepage: URL? = nil,
                enabled: Bool = true, bundled: Bool = false, managable: Bool = true, pending: Bool = false, safeModeVictim: Bool = false) {
        self.key = key
        self.name = name
        self.version = version
        self.author = author
        self.summary = summary
        self.homepage = homepage
        self.enabled = enabled
        self.bundled = bundled
        self.managable = managable
        self.pending = pending
        self.safeModeVictim = safeModeVictim
    }

    init?(_ json: JSONValue) {
        guard let key = json["key"]?.stringValue else { return nil }
        self.init(
            key: key,
            name: json["name"]?.stringValue ?? key,
            version: json["version"]?.stringValue,
            author: json["author"]?.stringValue,
            summary: json["description"]?.stringValue,
            homepage: json["url"]?.stringValue.flatMap(URL.init(string:)),
            enabled: json["enabled"]?.boolValue ?? false,
            bundled: json["bundled"]?.boolValue ?? false,
            managable: json["managable"]?.boolValue ?? true,
            pending: ["pending_enable", "pending_disable", "pending_install", "pending_uninstall"].contains { json[$0]?.boolValue == true },
            safeModeVictim: json["safe_mode_victim"]?.boolValue ?? false
        )
    }
}

/// What OctoPrint said after a plugin change.
public struct PluginChange: Sendable, Hashable {
    public var needsRestart: Bool
    public var plugin: InstalledPlugin?
}

extension OctoPrintClient {
    static let pluginManagerID = "pluginmanager"

    /// Every installed plugin. OctoPrint 1.6 and later have a dedicated endpoint; older versions answer the plugin's
    /// simple API.
    public func installedPlugins() async throws -> [InstalledPlugin] {
        let json: JSONValue
        do {
            json = try await get("plugin/\(Self.pluginManagerID)/plugins")
        } catch OctoPrintError.http(status: 404, _) {
            json = try await pluginGet(Self.pluginManagerID)
        }
        return (json["plugins"]?.arrayValue ?? []).compactMap(InstalledPlugin.init)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Switches a plugin on or off.
    public func togglePlugin(_ key: String) async throws -> PluginChange {
        Self.change(try await pluginCommand(Self.pluginManagerID, "toggle", parameters: ["plugin": .string(key)]))
    }

    public func uninstallPlugin(_ key: String) async throws -> PluginChange {
        Self.change(try await pluginCommand(Self.pluginManagerID, "uninstall", parameters: ["plugin": .string(key)]))
    }

    /// Asks the Software Update plugin to update these components (`octoprint` or plugin keys). OctoPrint restarts
    /// afterwards.
    public func updateSoftware(_ targets: [String]) async throws {
        try await post("plugin/softwareupdate/update", body: ["targets": .array(targets.map(JSONValue.string))] as CommandBody)
    }

    private static func change(_ json: JSONValue) -> PluginChange {
        PluginChange(needsRestart: json["needs_restart"]?.boolValue ?? false, plugin: json["plugin"].flatMap(InstalledPlugin.init))
    }
}
