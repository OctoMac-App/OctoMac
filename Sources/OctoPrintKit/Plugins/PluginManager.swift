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

/// A plugin from OctoPrint's official plugin repository (plugins.octoprint.org), as the Plugin Manager lists it.
public struct RepositoryPlugin: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String?
    public var author: String?
    public var homepage: URL?
    /// Its page on plugins.octoprint.org.
    public var page: URL?
    /// What the Plugin Manager installs.
    public var archive: URL
    /// Works with this OctoPrint, its Python and its operating system, by the plugin's own account.
    public var compatible: Bool
    /// Marked as abandoned by the repository: nobody looks after it any more.
    public var abandoned: Bool
    /// About how many OctoPrint servers used it last month.
    public var users: Int
    public var followDependencyLinks: Bool

    public init(id: String, title: String, summary: String? = nil, author: String? = nil, homepage: URL? = nil, page: URL? = nil,
                archive: URL, compatible: Bool = true, abandoned: Bool = false, users: Int = 0, followDependencyLinks: Bool = false) {
        self.id = id
        self.title = title
        self.summary = summary
        self.author = author
        self.homepage = homepage
        self.page = page
        self.archive = archive
        self.compatible = compatible
        self.abandoned = abandoned
        self.users = users
        self.followDependencyLinks = followDependencyLinks
    }

    init?(_ json: JSONValue) {
        guard let id = json["id"]?.stringValue, let archive = json["archive"]?.stringValue.flatMap(URL.init(string:)) else { return nil }
        let checks = json["is_compatible"]?.objectValue?.values.compactMap(\.boolValue) ?? []
        self.init(
            id: id,
            title: json["title"]?.stringValue ?? id,
            summary: json["description"]?.stringValue,
            author: json["author"]?.stringValue,
            homepage: json["homepage"]?.stringValue.flatMap(URL.init(string:)),
            page: json["page"]?.stringValue.flatMap(URL.init(string:)),
            archive: archive,
            compatible: !checks.contains(false),
            abandoned: json["abandoned"]?.boolValue == true || (json["attributes"]?.arrayValue ?? []).contains { $0.stringValue == "abandoned" },
            users: json["stats"]?["instances_month"]?.intValue ?? 0,
            followDependencyLinks: json["follow_dependency_links"]?.boolValue ?? false
        )
    }
}

/// The Plugin Manager's view of things: what's installed, and whether it can install more.
public struct PluginManagerStatus: Sendable, Hashable {
    public var plugins: [InstalledPlugin]
    /// OctoPrint started in safe mode, with every added plugin switched off.
    public var safeMode: Bool
    /// The Pi can reach the internet, so it can download plugins.
    public var online: Bool
    /// OctoPrint found pip, which it needs to install anything.
    public var canInstall: Bool
}

/// What the Plugin Manager pushes while it works: lines of its install log, and the result.
public enum PluginManagerMessage: Sendable, Equatable {
    case log([String])
    /// The end of an install (or another action). `reason` says why it failed.
    case result(action: String, success: Bool, needsRestart: Bool, reason: String?, plugin: InstalledPlugin?)

    public init?(_ data: JSONValue) {
        switch data["type"]?.stringValue {
        case "loglines":
            let lines = (data["loglines"]?.arrayValue ?? []).compactMap { $0["line"]?.stringValue }
            self = .log(lines)
        case "result":
            self = .result(action: data["action"]?.stringValue ?? "",
                           success: data["result"]?.boolValue ?? false,
                           needsRestart: data["needs_restart"]?.boolValue ?? false,
                           reason: data["reason"]?.stringValue,
                           plugin: data["plugin"].flatMap(InstalledPlugin.init))
        default:
            return nil
        }
    }
}

/// What OctoPrint said after a plugin change.
public struct PluginChange: Sendable, Hashable {
    public var needsRestart: Bool
    public var plugin: InstalledPlugin?
}

extension OctoPrintClient {
    public static let pluginManagerID = "pluginmanager"

    /// Every installed plugin. OctoPrint 1.6 and later have a dedicated endpoint; older versions answer the plugin's
    /// simple API.
    public func installedPlugins() async throws -> [InstalledPlugin] {
        try await pluginManagerStatus().plugins
    }

    /// The installed plugins, plus whether OctoPrint is in safe mode and able to install more.
    public func pluginManagerStatus() async throws -> PluginManagerStatus {
        let json: JSONValue
        do {
            json = try await get("plugin/\(Self.pluginManagerID)/plugins")
        } catch OctoPrintError.http(status: 404, _) {
            json = try await pluginGet(Self.pluginManagerID)
        }
        let plugins = (json["plugins"]?.arrayValue ?? []).compactMap(InstalledPlugin.init)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return PluginManagerStatus(plugins: plugins,
                                   safeMode: json["safe_mode"]?.boolValue ?? false,
                                   online: json["online"]?.boolValue ?? true,
                                   canInstall: json["pip"]?["available"]?.boolValue ?? true)
    }

    /// OctoPrint's official plugin repository, most used first. Empty when OctoPrint can't reach it.
    public func pluginRepository(refresh: Bool = false) async throws -> [RepositoryPlugin] {
        let query = refresh ? [URLQueryItem(name: "refresh", value: "true")] : []
        let json: JSONValue
        do {
            json = try await get("plugin/\(Self.pluginManagerID)/repository", query: query)
        } catch OctoPrintError.http(status: 404, _) {
            json = try await pluginGet(Self.pluginManagerID, query: query)
        }
        return (json["repository"]?["plugins"]?.arrayValue ?? []).compactMap(RepositoryPlugin.init)
            .sorted { $0.users != $1.users ? $0.users > $1.users : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Starts installing a plugin from the repository. OctoPrint works in the background and pushes its progress as
    /// `PluginManagerMessage`s.
    public func installPlugin(_ plugin: RepositoryPlugin) async throws {
        _ = try await pluginCommand(Self.pluginManagerID, "install", parameters: [
            "url": .string(plugin.archive.absoluteString),
            "dependency_links": .bool(plugin.followDependencyLinks),
            "from_repo": .bool(true),
        ])
    }

    /// Installs a plugin from an archive's web address. Progress comes as push messages, like a plugin from the list.
    public func installPlugin(from url: URL) async throws {
        _ = try await pluginCommand(Self.pluginManagerID, "install", parameters: ["url": .string(url.absoluteString)])
    }

    /// Uploads a plugin archive (.zip, .tar.gz), a single-file plugin (.py) or a plugin list (.json) and installs it.
    public func installPlugin(fileURL: URL) async throws {
        var form = MultipartForm()
        form.addFile(name: "file", filename: fileURL.lastPathComponent, contentType: "application/octet-stream", data: try Data(contentsOf: fileURL))
        var request = makeRequest(.post, "plugin/\(Self.pluginManagerID)/upload_file")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        _ = try await upload(request, body: form.encoded(), progress: { _ in })
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
