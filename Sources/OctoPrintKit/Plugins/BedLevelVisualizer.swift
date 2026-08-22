import Foundation

/// Support for the Bed Level Visualizer plugin (https://github.com/jneilliii/OctoPrint-BedLevelVisualizer).
///
/// To measure the bed, the client sends `@BEDLEVELVISUALIZER` followed by the G-code from the plugin's settings
/// (for example `G28 W`, `G80`, `G81` on a Prusa). The plugin reads the probe report from the printer and pushes
/// `{"processing": true}` and then `{"mesh": [[z, ...], ...], "bed": {...}}`, or `{"error": "..."}`.
/// Like the plugin's own page, clients save the latest mesh back into the plugin's settings when `save_mesh` is on.
public enum BedLevelVisualizer {
    public static let pluginID = "bedlevelvisualizer"

    /// A measured bed. `z[row][column]`, rows running along Y and columns along X. Missing points are nil.
    public struct Mesh: Sendable, Hashable {
        public var z: [[Double?]]
        /// Bed positions (mm) of each column and row.
        public var x: [Double]
        public var y: [Double]
        public var measured: String?

        public init(z: [[Double?]], x: [Double], y: [Double], measured: String? = nil) {
            self.z = z
            self.x = x
            self.y = y
            self.measured = measured
        }

        public var values: [Double] { z.flatMap { $0.compactMap { $0 } } }
        public var minimum: Double? { values.min() }
        public var maximum: Double? { values.max() }
        /// Highest point minus lowest point.
        public var spread: Double? { minimum.flatMap { low in maximum.map { $0 - low } } }
        public var isEmpty: Bool { values.isEmpty }
    }

    public struct Settings: Sendable, Hashable {
        /// The G-code that probes the bed, one command per line.
        public var command: String
        public var saveMesh: Bool
        /// Seconds to wait before giving up on a measurement.
        public var timeout: Double
        public var stored: Mesh?

        public init?(settings: JSONValue?) {
            guard let plugin = settings?.value(at: "plugins", BedLevelVisualizer.pluginID) else { return nil }
            command = plugin["command"]?.stringValue ?? ""
            saveMesh = plugin["save_mesh"]?.boolValue ?? true
            timeout = plugin["timeout"]?.doubleValue ?? 1800
            let z = BedLevelVisualizer.grid(plugin["stored_mesh"])
            if z.isEmpty {
                stored = nil
            } else {
                let x = (plugin["stored_mesh_x"]?.arrayValue ?? []).compactMap(\.doubleValue)
                let y = (plugin["stored_mesh_y"]?.arrayValue ?? []).compactMap(\.doubleValue)
                let timestamp = plugin["mesh_timestamp"]?.stringValue
                stored = Mesh(z: z, x: x, y: y, measured: timestamp?.isEmpty == false ? timestamp : nil)
            }
        }

        public var commandLines: [String] {
            command.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }

    public enum Message: Sendable, Equatable {
        case processing
        case mesh(Mesh)
        case error(String)

        public init?(_ data: JSONValue) {
            if let rows = data["mesh"], case let z = BedLevelVisualizer.grid(rows), !z.isEmpty {
                self = .mesh(BedLevelVisualizer.mesh(z: z, bed: data["bed"]))
            } else if let error = data["error"]?.stringValue {
                self = .error(error)
            } else if data["processing"]?.boolValue == true || data["BLV"]?.stringValue == "BLVPROCESSINGON" {
                self = .processing
            } else {
                return nil
            }
        }
    }

    static func grid(_ json: JSONValue?) -> [[Double?]] {
        (json?.arrayValue ?? []).map { row in (row.arrayValue ?? []).map(\.doubleValue) }.filter { !$0.isEmpty }
    }

    /// Spreads the columns and rows evenly across the probed area, as the plugin's own page does.
    static func mesh(z: [[Double?]], bed: JSONValue?) -> Mesh {
        let columns = z.first?.count ?? 0
        let rows = z.count
        let xMin = bed?["x_min"]?.doubleValue ?? 0, xMax = bed?["x_max"]?.doubleValue ?? Double(max(columns - 1, 1))
        let yMin = bed?["y_min"]?.doubleValue ?? 0, yMax = bed?["y_max"]?.doubleValue ?? Double(max(rows - 1, 1))
        func spread(_ count: Int, _ low: Double, _ high: Double) -> [Double] {
            guard count > 1 else { return [low] }
            return (0..<count).map { (low + Double($0) / Double(count - 1) * (high - low)).rounded() }
        }
        return Mesh(z: z, x: spread(columns, xMin, xMax), y: spread(rows, yMin, yMax))
    }
}

extension OctoPrintClient {
    /// Starts a bed measurement using the plugin's G-code.
    public func measureBed(commands: [String]) async throws {
        try await sendGcode(["@BEDLEVELVISUALIZER"] + commands.filter { $0 != "@BEDLEVELVISUALIZER" })
    }

    /// Tells the plugin to stop waiting for a measurement.
    public func cancelBedMeasurement() async throws {
        _ = try await pluginGet(BedLevelVisualizer.pluginID, query: [URLQueryItem(name: "stopProcessing", value: "true")])
    }

    /// Saves a mesh into the plugin's settings, so it's still there next time (here and in OctoPrint).
    public func storeBedMesh(_ mesh: BedLevelVisualizer.Mesh, measured: String) async throws {
        let z = JSONValue.array(mesh.z.map { .array($0.map { $0.map(JSONValue.number) ?? .null }) })
        let plugin: JSONValue = .object([
            "stored_mesh": z,
            "stored_mesh_x": .array(mesh.x.map(JSONValue.number)),
            "stored_mesh_y": .array(mesh.y.map(JSONValue.number)),
            "mesh_timestamp": .string(measured),
        ])
        _ = try await saveSettings(.object(["plugins": .object([BedLevelVisualizer.pluginID: plugin])]))
    }

    /// Changes the G-code the plugin sends to measure the bed.
    public func setBedMeasureCommand(_ command: String) async throws {
        _ = try await saveSettings(.object(["plugins": .object([BedLevelVisualizer.pluginID: .object(["command": .string(command)])])]))
    }
}
