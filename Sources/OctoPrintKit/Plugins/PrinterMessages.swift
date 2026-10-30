import Foundation

/// OctoPrint's bundled Action Command Prompt plugin: questions the firmware asks (`//action:prompt_begin`, choices,
/// `prompt_show`), such as "Filament runout. Continue?". The plugin pushes `{"action": "show", "text", "choices"}` and
/// `{"action": "close"}`, and an answer is sent back to the printer as `M876 S<choice>`.
public enum ActionPrompt {
    public static let pluginID = "action_command_prompt"

    public struct Prompt: Sendable, Hashable {
        public var text: String
        public var choices: [String]

        public init(text: String, choices: [String]) {
            self.text = text
            self.choices = choices
        }

        init?(_ json: JSONValue) {
            guard let text = json["text"]?.stringValue else { return nil }
            self.init(text: text, choices: (json["choices"]?.arrayValue ?? []).compactMap(\.stringValue))
        }
    }

    public enum Message: Sendable, Equatable {
        case show(Prompt)
        case close

        public init?(_ data: JSONValue) {
            switch data["action"]?.stringValue {
            case "show":
                guard let prompt = Prompt(data) else { return nil }
                self = .show(prompt)
            case "close": self = .close
            default: return nil
            }
        }
    }
}

/// OctoPrint's bundled Action Command Notification plugin: messages the firmware sends with `//action:notification`,
/// such as "Heating done" or "Print paused". The plugin keeps a list, and pushes `{"message": ...}` for each new one
/// and an empty object when the list is cleared.
public enum ActionNotification {
    public static let pluginID = "action_command_notification"

    public struct Note: Sendable, Hashable, Identifiable {
        public var date: Date
        public var message: String
        public var id: String { "\(date.timeIntervalSince1970)-\(message)" }

        public init(date: Date, message: String) {
            self.date = date
            self.message = message
        }
    }

    public enum Message: Sendable, Equatable {
        case added(String)
        case cleared

        public init(_ data: JSONValue) {
            if let message = data["message"]?.stringValue { self = .added(message) } else { self = .cleared }
        }
    }

    static func notes(_ json: JSONValue) -> [Note] {
        (json["notifications"]?.arrayValue ?? []).compactMap { entry in
            guard let message = entry["message"]?.stringValue else { return nil }
            return Note(date: Date(timeIntervalSince1970: entry["timestamp"]?.doubleValue ?? 0), message: message)
        }
    }
}

extension OctoPrintClient {
    /// The question the printer is waiting on, if any.
    public func actionPrompt() async throws -> ActionPrompt.Prompt? {
        ActionPrompt.Prompt(try await pluginGet(ActionPrompt.pluginID))
    }

    /// Answers the printer's question with the choice at `index`.
    public func answerActionPrompt(_ index: Int) async throws {
        _ = try await pluginCommand(ActionPrompt.pluginID, "select", parameters: ["choice": .number(Double(index))])
    }

    /// Messages the printer has sent since OctoPrint started, oldest first.
    public func printerNotifications() async throws -> [ActionNotification.Note] {
        ActionNotification.notes(try await pluginGet(ActionNotification.pluginID))
    }

    public func clearPrinterNotifications() async throws {
        _ = try await pluginCommand(ActionNotification.pluginID, "clear")
    }
}

/// OctoPrint's Health Check plugin (OctoPrint 1.11 and later): checks on the server itself, such as a nearly full
/// SD card or an old version of Python.
public enum HealthCheck {
    public static let pluginID = "health_check"

    public enum Result: String, Sendable {
        case ok, warning, issue
    }

    public struct Item: Sendable, Hashable, Identifiable {
        /// Which check: "filesystem_storage", "octoprint_freshness", "python_eol" and so on.
        public var key: String
        public var result: Result
        public var context: JSONValue
        public var id: String { key }

        public init(key: String, result: Result, context: JSONValue = .null) {
            self.key = key
            self.result = result
            self.context = context
        }
    }

    static func items(_ json: JSONValue) -> [Item] {
        guard case .object(let health) = json["health"] ?? .null else { return [] }
        return health.compactMap { key, value in
            guard let result = value["result"]?.stringValue.flatMap(Result.init) else { return nil }
            return Item(key: key, result: result, context: value["context"] ?? .null)
        }
        .sorted { $0.key < $1.key }
    }
}

/// OctoPrint's bundled Firmware Check plugin: warnings about printer firmware that's unsafe (thermal runaway
/// protection switched off), known to be broken, or a development build.
public enum FirmwareCheck {
    public static let pluginID = "firmware_check"

    public struct Warning: Sendable, Hashable, Identifiable {
        /// "firmware-unsafe", "firmware-broken", "firmware-development" or "firmware-hostcommands".
        public var type: String
        public var message: String
        /// "critical", "warning" or "info".
        public var severity: String
        public var url: URL?
        public var id: String { type }

        public init(type: String, message: String, severity: String, url: URL? = nil) {
            self.type = type
            self.message = message
            self.severity = severity
            self.url = url
        }

        public var isCritical: Bool { severity != "info" && severity != "warning" }
    }

    static func warnings(_ json: JSONValue) -> [Warning] {
        guard case .object(let warnings) = json else { return [] }
        return warnings.compactMap { type, value in
            guard let message = value["message"]?.stringValue else { return nil }
            return Warning(type: type, message: message, severity: value["severity"]?.stringValue ?? "critical",
                           url: value["url"]?.stringValue.flatMap(URL.init(string:)))
        }
        .sorted { $0.type < $1.type }
    }
}

extension OctoPrintClient {
    /// The server's health checks. `refresh` runs them again rather than using the last results.
    public func healthChecks(refresh: Bool = false) async throws -> [HealthCheck.Item] {
        HealthCheck.items(try await pluginGet(HealthCheck.pluginID, query: refresh ? [URLQueryItem(name: "refresh", value: "true")] : []))
    }

    /// Warnings about the connected printer's firmware. Empty while no printer is connected.
    public func firmwareWarnings() async throws -> [FirmwareCheck.Warning] {
        FirmwareCheck.warnings(try await pluginGet(FirmwareCheck.pluginID))
    }
}

/// What the Software Update plugin pushes while it updates: the output of pip, and how each part went.
public enum SoftwareUpdateMessage: Sendable, Equatable {
    case log([String])
    case updating(target: String)
    case failed(target: String, reason: String?)
    /// Everything's updated and OctoPrint is restarting.
    case restarting
    /// Updated, but OctoPrint couldn't restart itself.
    case restartManually
    case restartFailed
    /// Updated with no restart needed.
    case success
    case error

    public static let pluginID = "softwareupdate"

    public init?(_ data: JSONValue) {
        let body = data["data"] ?? .null
        switch data["type"]?.stringValue {
        case "loglines":
            self = .log((body["loglines"]?.arrayValue ?? []).compactMap { $0["line"]?.stringValue })
        case "updating":
            self = .updating(target: body["target"]?.stringValue ?? "")
        case "update_failed":
            self = .failed(target: body["target"]?.stringValue ?? "", reason: body["reason"]?.stringValue)
        case "restarting": self = .restarting
        case "restart_manually": self = .restartManually
        case "restart_failed": self = .restartFailed
        case "success": self = .success
        case "error": self = .error
        default: return nil
        }
    }
}
