import Foundation

/// Buttons people set up in OctoPrint's own settings (`controls` in config.yaml), from
/// `GET /api/printer/command/custom`. A control sends G-code commands or runs a G-code script, and may ask for
/// values first (`%(name)s` placeholders). Controls can be grouped into named containers.
public indirect enum CustomControl: Sendable, Hashable, Identifiable {
    case group(name: String, children: [CustomControl])
    case action(Action)

    public struct Input: Sendable, Hashable, Identifiable {
        public var name: String
        public var parameter: String
        public var defaultValue: String
        public var id: String { parameter }
    }

    public struct Action: Sendable, Hashable, Identifiable {
        public var name: String
        public var commands: [String]
        public var script: String?
        public var inputs: [Input]
        /// Text to show before running, if the control asks for confirmation.
        public var confirm: String?
        public var id: String { name + (script ?? commands.joined(separator: "|")) }

        /// The commands with each `%(parameter)s` replaced by its value.
        public func resolvedCommands(_ values: [String: String]) -> [String] {
            commands.map { command in
                inputs.reduce(command) { text, input in
                    text.replacingOccurrences(of: "%(\(input.parameter))s", with: values[input.parameter] ?? input.defaultValue)
                }
            }
        }
    }

    public var id: String {
        switch self {
        case .group(let name, let children): "group:" + name + children.map(\.id).joined()
        case .action(let action): "action:" + action.id
        }
    }

    public static func parse(_ json: JSONValue) -> [CustomControl] {
        (json["controls"]?.arrayValue ?? json.arrayValue ?? []).compactMap(parseOne)
    }

    private static func parseOne(_ json: JSONValue) -> CustomControl? {
        if let children = json["children"]?.arrayValue {
            let parsed = children.compactMap(parseOne)
            return parsed.isEmpty ? nil : .group(name: json["name"]?.stringValue ?? "", children: parsed)
        }
        let commands = json["commands"]?.arrayValue?.compactMap(\.stringValue) ?? json["command"]?.stringValue.map { [$0] } ?? []
        let script = json["script"]?.stringValue
        guard !commands.isEmpty || script != nil, let name = json["name"]?.stringValue else { return nil }
        let inputs = (json["input"]?.arrayValue ?? []).compactMap { input -> Input? in
            guard let parameter = input["parameter"]?.stringValue else { return nil }
            let fallback = input["default"].map { $0.stringValue ?? $0.doubleValue.map { Self.number($0) } ?? "" } ?? ""
            return Input(name: input["name"]?.stringValue ?? parameter, parameter: parameter, defaultValue: fallback)
        }
        return .action(Action(name: name, commands: commands, script: script, inputs: inputs, confirm: json["confirm"]?.stringValue))
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// A camera from OctoPrint's webcam settings (OctoPrint 1.9 and later can have several).
public struct Webcam: Sendable, Hashable, Identifiable {
    public var name: String
    public var displayName: String
    public var stream: String
    public var flipH: Bool
    public var flipV: Bool
    public var rotate90: Bool
    public var id: String { name }

    /// Every camera with a stream, from `settings.webcam.webcams`, falling back to the single classic webcam.
    public static func list(from settings: JSONValue?) -> [Webcam] {
        let webcams = (settings?.value(at: "webcam", "webcams")?.arrayValue ?? []).compactMap { cam -> Webcam? in
            let stream = cam.value(at: "compat", "stream")?.stringValue ?? cam.value(at: "extras", "stream")?.stringValue
            guard let stream, !stream.isEmpty, let name = cam["name"]?.stringValue else { return nil }
            return Webcam(name: name, displayName: cam["displayName"]?.stringValue ?? name, stream: stream,
                          flipH: cam["flipH"]?.boolValue ?? false, flipV: cam["flipV"]?.boolValue ?? false,
                          rotate90: cam["rotate90"]?.boolValue ?? false)
        }
        if !webcams.isEmpty { return webcams }
        let legacy = settings?.value(at: "plugins", "classicwebcam") ?? settings?["webcam"]
        guard let stream = (settings?.value(at: "plugins", "classicwebcam", "stream") ?? settings?.value(at: "webcam", "streamUrl"))?.stringValue,
              !stream.isEmpty else { return [] }
        return [Webcam(name: "classic", displayName: String(localized: "Camera"), stream: stream,
                       flipH: legacy?["flipH"]?.boolValue ?? false, flipV: legacy?["flipV"]?.boolValue ?? false,
                       rotate90: legacy?["rotate90"]?.boolValue ?? false)]
    }
}

extension OctoPrintClient {
    public func customControlList() async throws -> [CustomControl] {
        CustomControl.parse(try await customControls())
    }

    /// Runs a G-code script set up in OctoPrint (`POST /api/printer/command {"script": ...}`).
    public func runScript(_ name: String, parameters: [String: String] = [:]) async throws {
        let context: JSONValue = .object(["parameters": .object(parameters.mapValues(JSONValue.string))])
        try await post("api/printer/command", body: ["script": .string(name), "context": context] as CommandBody)
    }

    /// Downloads a rendered timelapse video.
    public func timelapseData(_ file: TimelapseFile) async throws -> Data {
        let (data, _) = try await send(makeRequest(.get, "downloads/timelapse/\(file.name)"))
        return data
    }
}
