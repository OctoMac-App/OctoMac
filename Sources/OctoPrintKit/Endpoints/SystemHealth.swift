import Foundation

// System information, Raspberry Pi health, printer errors and software updates.

/// What the Pi Support plugin knows about power and temperature problems on a Raspberry Pi.
/// Under-voltage and overheating make the Pi slow down, a common cause of stuttering prints.
public struct ThrottleState: Sendable, Hashable {
    public var currentUndervoltage: Bool
    public var pastUndervoltage: Bool
    public var currentOverheat: Bool
    public var pastOverheat: Bool
    public var currentIssue: Bool
    public var pastIssue: Bool

    public init?(_ json: JSONValue?) {
        guard let json, json["current_issue"] != nil || json["raw_value"] != nil else { return nil }
        currentUndervoltage = json["current_undervoltage"]?.boolValue ?? false
        pastUndervoltage = json["past_undervoltage"]?.boolValue ?? false
        currentOverheat = json["current_overheat"]?.boolValue ?? false
        pastOverheat = json["past_overheat"]?.boolValue ?? false
        currentIssue = json["current_issue"]?.boolValue ?? false
        pastIssue = json["past_issue"]?.boolValue ?? false
    }
}

/// `GET /api/plugin/pi_support`: the Pi model, OctoPi version and throttle state.
public struct PiSupportInfo: Sendable, Hashable {
    public static let pluginID = "pi_support"

    public var model: String?
    public var octoPiVersion: String?
    public var throttle: ThrottleState?

    public init(_ json: JSONValue) {
        model = json["model"]?.stringValue
        octoPiVersion = json["octopi_version"]?.stringValue
        throttle = ThrottleState(json["throttle_state"])
    }

    /// A live throttle update pushed by the plugin (`{"type": "throttle_state", "state": {...}}`).
    public static func throttleUpdate(_ data: JSONValue) -> ThrottleState? {
        guard data["type"]?.stringValue == "throttle_state" else { return nil }
        return ThrottleState(data["state"])
    }
}

/// Why the printer last stopped with an error (`GET /api/printer/error`). Empty when there wasn't one.
public struct PrinterErrorInfo: Sendable, Hashable {
    public var error: String
    public var reason: String
    public var consequence: String?

    public init(_ json: JSONValue) {
        error = json["error"]?.stringValue ?? ""
        reason = json["reason"]?.stringValue ?? ""
        consequence = json["consequence"]?.stringValue
    }

    public var isEmpty: Bool { error.isEmpty }
}

/// One component the Software Update plugin keeps track of (OctoPrint itself or a plugin).
public struct SoftwareComponent: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var installed: String
    public var available: String?
    public var updateAvailable: Bool
    public var updatePossible: Bool

    public init(id: String, name: String, installed: String, available: String?, updateAvailable: Bool, updatePossible: Bool) {
        self.id = id
        self.name = name
        self.installed = installed
        self.available = available
        self.updateAvailable = updateAvailable
        self.updatePossible = updatePossible
    }
}

extension OctoPrintClient {
    /// `GET /api/system/info`: a flat dictionary of facts about the server, the Pi and the printer
    /// (for example `printer.firmware` and `env.plugins.pi_support.model`).
    public func systemInfo() async throws -> [String: JSONValue] {
        let json: JSONValue = try await get("api/system/info")
        return json["systeminfo"]?.objectValue ?? [:]
    }

    public func piSupport() async throws -> PiSupportInfo {
        PiSupportInfo(try await pluginGet(PiSupportInfo.pluginID))
    }

    public func lastPrinterError() async throws -> PrinterErrorInfo {
        PrinterErrorInfo(try await printerError())
    }

    /// Asks the Software Update plugin what's installed and what's newer. Uses the plugin's cached check
    /// unless `force` is set, which asks every source again (slower).
    public func softwareUpdates(force: Bool = false) async throws -> [SoftwareComponent] {
        let json: JSONValue = try await get("plugin/softwareupdate/check", query: force ? [URLQueryItem(name: "force", value: "true")] : [])
        return (json["information"]?.objectValue ?? [:]).map { key, value in
            SoftwareComponent(
                id: key,
                name: value["displayName"]?.stringValue ?? key,
                installed: value["displayVersion"]?.stringValue ?? value.value(at: "information", "local", "name")?.stringValue ?? "",
                available: value.value(at: "information", "remote", "name")?.stringValue,
                updateAvailable: value["updateAvailable"]?.boolValue ?? false,
                updatePossible: value["updatePossible"]?.boolValue ?? false
            )
        }
        .sorted { ($0.id == "octoprint" ? 0 : 1, $0.name.lowercased()) < ($1.id == "octoprint" ? 0 : 1, $1.name.lowercased()) }
    }

    /// Downloads a log file's contents.
    public func logContents(_ file: LogFile) async throws -> Data {
        let (data, _) = try await send(makeRequest(.get, "downloads/logs/\(file.name)"))
        return data
    }
}
