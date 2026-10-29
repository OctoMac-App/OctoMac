import Foundation

/// Support for the Prusa MMU plugin (https://github.com/jukebox42/Octoprint-PrusaMMU).
///
/// When a print starts on a printer with a Prusa Multi Material Unit, the plugin pauses and asks which filament
/// slot to use. It announces this with a push message (`{"plugin": "prusammu", "data": {"action": "show"}}`), and
/// waits for `POST /api/plugin/prusammu {"command": "select", "choice": <slot index | "skip">}`. If nobody answers
/// before its timeout, the print carries on with the slicer's choice (or, on the MK3, the printer asks itself).
public enum PrusaMMU {
    public static let pluginID = "prusammu"

    public struct Filament: Sendable, Hashable, Identifiable {
        /// Zero-based slot index, as sent back in `select`.
        public var index: Int
        public var name: String
        /// Hex colour such as `#FFFF00`, if set.
        public var color: String?
        public var id: Int { index }
    }

    /// The plugin's settings, from `settings.plugins.prusammu`.
    public struct Settings: Sendable, Hashable {
        public var filaments: [Filament]
        /// Seconds before an unanswered prompt times out.
        public var timeout: Double
        /// Whether slots are numbered from 0 rather than 1 when displayed.
        public var indexAtZero: Bool
        public var promptEnabled: Bool

        public init?(settings: JSONValue?) {
            guard let plugin = settings?.value(at: "plugins", PrusaMMU.pluginID) else { return nil }
            let count = plugin["filamentCount"]?.intValue ?? 5
            var filaments = (plugin["filament"]?.arrayValue ?? []).compactMap { entry -> Filament? in
                guard entry["enabled"]?.boolValue ?? true, let id = entry["id"]?.intValue else { return nil }
                let color = entry["color"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
                return Filament(index: id - 1, name: entry["name"]?.stringValue ?? "", color: color)
            }
            filaments = filaments.filter { $0.index >= 0 && $0.index < count }
            if filaments.isEmpty {
                filaments = (0..<count).map { Filament(index: $0, name: "", color: nil) }
            }
            self.filaments = filaments
            timeout = plugin["timeout"]?.doubleValue ?? 30
            indexAtZero = plugin["indexAtZero"]?.boolValue ?? false
            promptEnabled = plugin["enablePrompt"]?.boolValue ?? true
        }

        /// "Filament 2" or "2: Mango Yellow PETG", matching the plugin's own wording.
        public func label(for filament: Filament) -> String {
            let number = indexAtZero ? filament.index : filament.index + 1
            return filament.name.isEmpty ? String(localized: "Filament \(number)") : filament.name
        }

        public func number(for filament: Filament) -> Int { indexAtZero ? filament.index : filament.index + 1 }
    }

    /// What a plugin push message means for us.
    public enum Message: Sendable, Equatable {
        case showPrompt
        case closePrompt
        /// Current MMU state: the active tool (slot index) and the printer generation ("MK3", "MK4", ...).
        case state(tool: Int?, prusaVersion: String?)

        public init?(_ data: JSONValue) {
            switch data["action"]?.stringValue {
            case "show": self = .showPrompt
            case "close": self = .closePrompt
            case "nav":
                let tool = data["tool"]?.intValue ?? data["tool"]?.stringValue.flatMap(Int.init)
                self = .state(tool: tool, prusaVersion: data["prusaVersion"]?.stringValue)
            default: return nil
            }
        }
    }
}

extension OctoPrintClient {
    /// Answers the Prusa MMU plugin's filament prompt with a slot index, or `nil` to skip (MK3.5 and later only).
    public func selectMMUFilament(_ index: Int?) async throws {
        _ = try await pluginCommand(PrusaMMU.pluginID, "select", parameters: ["choice": index.map { JSONValue($0) } ?? "skip"])
    }

    /// Asks the plugin to resend its current state (arrives as a push message).
    public func refreshMMUState() async throws {
        _ = try await pluginCommand(PrusaMMU.pluginID, "getmmu")
    }
}
