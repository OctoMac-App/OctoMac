import Foundation

// https://docs.octoprint.org/en/main/api/datamodel.html#printer-related

public struct PrinterStateFlags: Codable, Sendable, Hashable {
    public var operational = false
    public var paused = false
    public var printing = false
    public var pausing = false
    public var cancelling = false
    public var resuming = false
    public var finishing = false
    public var sdReady = false
    public var error = false
    public var ready = false
    public var closedOrError = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        operational = try c.decodeIfPresent(Bool.self, forKey: .operational) ?? false
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        printing = try c.decodeIfPresent(Bool.self, forKey: .printing) ?? false
        pausing = try c.decodeIfPresent(Bool.self, forKey: .pausing) ?? false
        cancelling = try c.decodeIfPresent(Bool.self, forKey: .cancelling) ?? false
        resuming = try c.decodeIfPresent(Bool.self, forKey: .resuming) ?? false
        finishing = try c.decodeIfPresent(Bool.self, forKey: .finishing) ?? false
        sdReady = try c.decodeIfPresent(Bool.self, forKey: .sdReady) ?? false
        error = try c.decodeIfPresent(Bool.self, forKey: .error) ?? false
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        closedOrError = try c.decodeIfPresent(Bool.self, forKey: .closedOrError) ?? false
    }

    /// A job is loaded and either running or paused.
    public var isJobActive: Bool { printing || paused || pausing || cancelling || resuming || finishing }
}

public struct PrinterState: Codable, Sendable, Hashable {
    public var text: String
    public var flags: PrinterStateFlags
    public var error: String?

    public init(text: String, flags: PrinterStateFlags = .init(), error: String? = nil) {
        self.text = text
        self.flags = flags
        self.error = error
    }
}

public struct TemperatureData: Codable, Sendable, Hashable {
    public var actual: Double?
    public var target: Double?
    public var offset: Double?

    public init(actual: Double? = nil, target: Double? = nil, offset: Double? = nil) {
        self.actual = actual
        self.target = target
        self.offset = offset
    }
}

/// One temperature reading across all heaters, e.g. `{"time": 1395651928, "tool0": {...}, "bed": {...}}`.
public struct TemperatureSnapshot: Decodable, Sendable, Hashable {
    public var time: Date?
    public var heaters: [String: TemperatureData]

    public init(time: Date?, heaters: [String: TemperatureData]) {
        self.time = time
        self.heaters = heaters
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        var heaters: [String: TemperatureData] = [:]
        var time: Date?
        for key in c.allKeys {
            switch key.stringValue {
            case "time":
                time = (try? c.decode(Double.self, forKey: key)).map(Date.init(timeIntervalSince1970:))
            case "history":
                continue
            default:
                if let data = try? c.decode(TemperatureData.self, forKey: key) { heaters[key.stringValue] = data }
            }
        }
        self.time = time
        self.heaters = heaters
    }
}

/// `temperature` block of `GET /api/printer`: current readings plus optional `history`.
public struct TemperatureState: Decodable, Sendable, Hashable {
    public var current: TemperatureSnapshot
    public var history: [TemperatureSnapshot]

    public init(from decoder: Decoder) throws {
        current = try TemperatureSnapshot(from: decoder)
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        history = (try? c.decodeIfPresent([TemperatureSnapshot].self, forKey: AnyCodingKey("history"))) ?? []
    }
}

public struct SDState: Codable, Sendable, Hashable {
    public var ready: Bool
}

/// `GET /api/printer`
public struct PrinterStatus: Decodable, Sendable {
    public var state: PrinterState?
    public var temperature: TemperatureState?
    public var sd: SDState?
}

public enum HeaterKind: Sendable, Hashable {
    case tool(Int)
    case bed
    case chamber
    /// Prusa firmware reports ambient (`A`) and PINDA probe (`P`) readings alongside the heaters.
    case ambient
    case probe
    case other(String)

    public init(key: String) {
        if key == "bed" { self = .bed }
        else if key == "chamber" { self = .chamber }
        else if key == "A" { self = .ambient }
        else if key == "P" { self = .probe }
        else if key.hasPrefix("tool"), let index = Int(key.dropFirst(4)) { self = .tool(index) }
        else { self = .other(key) }
    }

    public var displayName: String {
        switch self {
        case .tool(let index): index == 0 ? String(localized: "Hotend") : String(localized: "Hotend \(index + 1)")
        case .bed: String(localized: "Bed")
        case .chamber: String(localized: "Chamber")
        case .ambient: String(localized: "Ambient")
        case .probe: String(localized: "Probe")
        case .other(let key): key.capitalized
        }
    }

    /// Whether this is a heater that accepts a target temperature (as opposed to a read-only sensor).
    public var isHeater: Bool {
        switch self {
        case .tool, .bed, .chamber: true
        case .ambient, .probe, .other: false
        }
    }
}
