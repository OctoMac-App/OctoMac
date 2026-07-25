import Foundation

// Settings, system, profiles, timelapse, logs, access control, slicing, languages, util, wizard.
// Free-form areas return `JSONValue`; promote to typed models as the UI grows into them.

extension OctoPrintClient {
    // MARK: Settings: https://docs.octoprint.org/en/main/api/settings.html

    public func settings() async throws -> JSONValue {
        try await get("api/settings")
    }

    /// Saves a partial settings tree, e.g. `["temperature": ["profiles": ...]]`.
    @discardableResult
    public func saveSettings(_ partial: JSONValue) async throws -> JSONValue {
        try await post("api/settings", body: partial)
    }

    public func regenerateSystemAPIKey() async throws -> JSONValue {
        try await post("api/settings/apikey", body: CommandBody())
    }

    // MARK: System: https://docs.octoprint.org/en/main/api/system.html

    public func systemCommands() async throws -> SystemCommandList {
        try await get("api/system/commands")
    }

    public func execute(_ command: SystemCommand) async throws {
        try await post("api/system/commands/\(command.source)/\(command.action)", body: CommandBody())
    }

    // MARK: Printer profiles: https://docs.octoprint.org/en/main/api/printerprofiles.html

    public func printerProfiles() async throws -> [PrinterProfile] {
        let list: PrinterProfileList = try await get("api/printerprofiles")
        return list.profiles.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func printerProfileJSON(_ id: String) async throws -> JSONValue {
        try await get("api/printerprofiles/\(id)")
    }

    public func addPrinterProfile(_ profile: JSONValue, basedOn: String? = nil) async throws -> JSONValue {
        var body: CommandBody = ["profile": profile]
        if let basedOn { body["basedOn"] = .string(basedOn) }
        return try await post("api/printerprofiles", body: body)
    }

    public func updatePrinterProfile(_ id: String, with profile: JSONValue) async throws -> JSONValue {
        try await patch("api/printerprofiles/\(id)", body: ["profile": profile] as CommandBody)
    }

    public func deletePrinterProfile(_ id: String) async throws {
        try await delete("api/printerprofiles/\(id)")
    }

    // MARK: Timelapse: https://docs.octoprint.org/en/main/api/timelapse.html

    public func timelapses(includeUnrendered: Bool = true) async throws -> TimelapseList {
        try await get("api/timelapse", query: [URLQueryItem(name: "unrendered", value: includeUnrendered ? "true" : "false")])
    }

    public func deleteTimelapse(_ name: String) async throws {
        try await delete("api/timelapse/\(name)")
    }

    public func renderTimelapse(_ name: String) async throws {
        try await post("api/timelapse/unrendered/\(name)", body: ["command": "render"] as CommandBody)
    }

    public func deleteUnrenderedTimelapse(_ name: String) async throws {
        try await delete("api/timelapse/unrendered/\(name)")
    }

    public func saveTimelapseConfig(_ config: JSONValue) async throws -> JSONValue {
        try await post("api/timelapse", body: config)
    }

    // MARK: Logs: https://docs.octoprint.org/en/main/bundledplugins/logging.html

    public func logFiles() async throws -> LogFileList {
        try await get("plugin/logging/logs")
    }

    public func deleteLogFile(_ name: String) async throws {
        try await delete("plugin/logging/logs/\(name)")
    }

    // MARK: Access control: https://docs.octoprint.org/en/main/api/access.html

    public func permissions() async throws -> JSONValue { try await get("api/access/permissions") }
    public func groups() async throws -> JSONValue { try await get("api/access/groups") }
    public func users() async throws -> JSONValue { try await get("api/access/users") }
    public func user(_ name: String) async throws -> JSONValue { try await get("api/access/users/\(name)") }

    public func addUser(name: String, password: String, active: Bool = true, groups: [String] = ["users"]) async throws -> JSONValue {
        try await post("api/access/users", body: [
            "name": .string(name), "password": .string(password), "active": .bool(active), "groups": JSONValue(groups),
        ] as CommandBody)
    }

    public func updateUser(_ name: String, with fields: JSONValue) async throws -> JSONValue {
        try await put("api/access/users/\(name)", body: fields)
    }

    public func deleteUser(_ name: String) async throws {
        try await delete("api/access/users/\(name)")
    }

    // MARK: Slicing: https://docs.octoprint.org/en/main/api/slicing.html

    public func slicers() async throws -> JSONValue { try await get("api/slicing") }

    // MARK: Languages: https://docs.octoprint.org/en/main/api/languages.html

    public func languages() async throws -> JSONValue { try await get("api/languages") }

    // MARK: Util: https://docs.octoprint.org/en/main/api/util.html

    /// Lets OctoPrint test a path/url/server on our behalf (`POST /api/util/test`).
    public func test(_ body: JSONValue) async throws -> JSONValue {
        try await post("api/util/test", body: body)
    }

    // MARK: Wizard: https://docs.octoprint.org/en/main/api/wizard.html

    public func wizard() async throws -> JSONValue { try await get("setup/wizard") }

    // MARK: Plugins

    /// `GET /api/plugin/{id}` for SimpleApiPlugins.
    public func pluginGet(_ plugin: String, query: [URLQueryItem] = []) async throws -> JSONValue {
        try await get("api/plugin/\(plugin)", query: query)
    }

    /// `POST /api/plugin/{id}` with `{"command": ..., ...}` for SimpleApiPlugins.
    public func pluginCommand(_ plugin: String, _ command: String, parameters: CommandBody = [:]) async throws -> JSONValue {
        var body = parameters
        body["command"] = .string(command)
        let (data, _) = try await send(makeRequest(.post, "api/plugin/\(plugin)", body: Self.encoder.encode(body)))
        return data.isEmpty ? .null : ((try? Self.decoder.decode(JSONValue.self, from: data)) ?? .null)
    }
}
