import Foundation

/// `GET /api/version`
public struct VersionInfo: Codable, Sendable, Hashable {
    public var api: String
    public var server: String
    public var text: String?
}

/// `GET /api/server`
public struct ServerInfo: Codable, Sendable, Hashable {
    public var version: String
    /// `nil` when not in safe mode, otherwise the reason (`settings`, `incomplete_startup`, `flag`).
    public var safemode: String?
}

/// `POST /api/login` / `GET /api/currentuser`
public struct UserRecord: Decodable, Sendable, Hashable {
    public var name: String?
    public var session: String?
    public var active: Bool?
    public var admin: Bool?
    public var groups: [String]?
    public var permissions: [String]?

    enum CodingKeys: String, CodingKey { case name, session, active, admin, groups, permissions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        session = try? c.decodeIfPresent(String.self, forKey: .session)
        active = try? c.decodeIfPresent(Bool.self, forKey: .active)
        admin = try? c.decodeIfPresent(Bool.self, forKey: .admin)
        // Groups/permissions are either plain strings or `{key: ...}` objects depending on endpoint & version.
        groups = Self.keys(try? c.decodeIfPresent([JSONValue].self, forKey: .groups))
        permissions = Self.keys(try? c.decodeIfPresent([JSONValue].self, forKey: .permissions))
    }

    private static func keys(_ values: [JSONValue]?) -> [String]? {
        values?.compactMap { $0.stringValue ?? $0["key"]?.stringValue }
    }

    public func has(_ permission: String) -> Bool {
        admin == true || permissions?.contains(permission) == true
    }
}

/// `GET /api/connection`
public struct ConnectionInfo: Decodable, Sendable, Hashable {
    public struct Current: Decodable, Sendable, Hashable {
        public var state: String
        public var port: String?
        public var baudrate: Int?
        public var printerProfile: String?
    }

    public struct ProfileRef: Decodable, Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
    }

    public struct Options: Decodable, Sendable, Hashable {
        public var ports: [String]
        public var baudrates: [Int]
        public var printerProfiles: [ProfileRef]
        public var portPreference: String?
        public var baudratePreference: Int?
        public var printerProfilePreference: String?
        public var autoconnect: Bool?
    }

    public var current: Current
    public var options: Options

    public var isConnected: Bool {
        !["Closed", "Offline", "Error", "Offline after error"].contains(where: { current.state.hasPrefix($0) })
    }
}

public struct ConnectRequest: Sendable {
    public var port: String?
    public var baudrate: Int?
    public var printerProfile: String?
    public var save = false
    public var autoconnect: Bool?

    public init(port: String? = nil, baudrate: Int? = nil, printerProfile: String? = nil, save: Bool = false, autoconnect: Bool? = nil) {
        self.port = port
        self.baudrate = baudrate
        self.printerProfile = printerProfile
        self.save = save
        self.autoconnect = autoconnect
    }

    var body: CommandBody {
        var body: CommandBody = ["command": "connect", "save": .bool(save)]
        if let port { body["port"] = .string(port) }
        if let baudrate { body["baudrate"] = JSONValue(baudrate) }
        if let printerProfile { body["printerProfile"] = .string(printerProfile) }
        if let autoconnect { body["autoconnect"] = .bool(autoconnect) }
        return body
    }
}

/// `GET /api/system/commands`
public struct SystemCommand: Decodable, Sendable, Hashable, Identifiable {
    public var action: String
    public var name: String
    public var source: String
    public var confirm: String?
    public var resource: String?

    public var id: String { "\(source)/\(action)" }
}

public struct SystemCommandList: Decodable, Sendable {
    public var core: [SystemCommand]
    public var custom: [SystemCommand]

    public var all: [SystemCommand] { core + custom }
}

/// `GET /api/printerprofiles`
public struct PrinterProfile: Decodable, Sendable, Hashable, Identifiable {
    public struct Volume: Decodable, Sendable, Hashable {
        public var width: Double?
        public var depth: Double?
        public var height: Double?
        public var formFactor: String?
        public var origin: String?
    }

    public struct Extruder: Decodable, Sendable, Hashable {
        public var count: Int?
        public var nozzleDiameter: Double?
        public var sharedNozzle: Bool?
    }

    public struct Axis: Decodable, Sendable, Hashable {
        public var speed: Double?
        public var inverted: Bool?
    }

    public var id: String
    public var name: String
    public var model: String?
    public var color: String?
    public var `default`: Bool?
    public var current: Bool?
    public var heatedBed: Bool?
    public var heatedChamber: Bool?
    public var volume: Volume?
    public var extruder: Extruder?
    public var axes: [String: Axis]?
}

public struct PrinterProfileList: Decodable, Sendable {
    public var profiles: [String: PrinterProfile]
}

/// `GET /api/timelapse`
public struct TimelapseFile: Decodable, Sendable, Hashable, Identifiable {
    public var name: String
    public var size: String?
    public var bytes: Int?
    public var date: String?
    public var url: String?
    public var thumbnail: String?

    public var id: String { name }
}

public struct TimelapseList: Decodable, Sendable {
    public var config: JSONValue?
    public var enabled: Bool?
    public var files: [TimelapseFile]
    public var unrendered: [TimelapseFile]?

    public var settings: TimelapseSettings { TimelapseSettings(config) }
}

/// How OctoPrint makes timelapses: https://docs.octoprint.org/en/main/api/timelapse.html
public struct TimelapseSettings: Sendable, Hashable {
    public enum Mode: String, Sendable, CaseIterable {
        case off
        /// A picture every time the print moves up a layer.
        case zchange
        /// A picture every few seconds.
        case timed
    }

    /// Which prints get made into a video afterwards.
    public enum Render: String, Sendable, CaseIterable {
        case always, success, failure, never
    }

    public var mode: Mode = .off
    public var fps = 25
    /// Seconds the last picture is held at the end of the video.
    public var postRoll = 0
    /// Seconds between pictures, for timed timelapses.
    public var interval = 10
    /// The shortest time between pictures on layer changes, so vase mode or tiny layers don't flood the video.
    public var minDelay = 5.0
    /// For prints that hop the nozzle up on retraction: hops of this height aren't taken as a new layer.
    public var retractionZHop = 0.0
    public var render = Render.always

    public init() {}

    public init(_ json: JSONValue?) {
        mode = json?["type"]?.stringValue.flatMap(Mode.init(rawValue:)) ?? .off
        fps = json?["fps"]?.intValue ?? fps
        postRoll = json?["postRoll"]?.intValue ?? postRoll
        interval = json?["interval"]?.intValue ?? interval
        minDelay = json?["minDelay"]?.doubleValue ?? minDelay
        retractionZHop = json?["retractionZHop"]?.doubleValue ?? retractionZHop
        render = json?["renderAfterPrint"]?.stringValue.flatMap(Render.init(rawValue:)) ?? render
    }

    /// What OctoPrint takes. Setting the type resets everything else, so every value goes every time.
    public var body: CommandBody {
        [
            "type": .string(mode.rawValue),
            "fps": .number(Double(max(fps, 1))),
            "postRoll": .number(Double(max(postRoll, 0))),
            "interval": .number(Double(max(interval, 1))),
            "minDelay": .number(max(minDelay, 0)),
            "retractionZHop": .number(max(retractionZHop, 0)),
            "renderAfterPrint": .string(render.rawValue),
        ]
    }
}

/// `GET /plugin/logging/logs`
public struct LogFile: Decodable, Sendable, Hashable, Identifiable {
    public var name: String
    public var size: Int?
    public var date: Double?
    public var refs: FileRefs?

    public var id: String { name }
}

public struct LogFileList: Decodable, Sendable {
    public var files: [LogFile]
    public var free: Int?
}
