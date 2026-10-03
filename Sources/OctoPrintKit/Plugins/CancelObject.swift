import Foundation

/// Support for the Cancel Objects plugin (https://github.com/paukstelis/OctoPrint-Cancelobject).
///
/// The plugin reads the object labels slicers put in G-code, and can skip one object's moves for the rest of the
/// print, so one failed part on a full plate doesn't spoil the others. It pushes `{"objects": [...]}` when the
/// list changes and `{"ActiveID": n}` as the printer moves between objects; `POST /api/plugin/cancelobject`
/// with `{"command": "cancel", "cancelled": id}` cancels one, and `{"command": "objlist"}` returns the list.
public enum CancelObject {
    public static let pluginID = "cancelobject"

    public struct Object: Sendable, Hashable, Identifiable {
        public var id: Int
        public var name: String
        public var cancelled: Bool
        /// Objects the plugin is set to leave alone (purge lines and the like).
        public var ignored: Bool
        /// Where the object sits on the bed (mm), once the plugin has seen its moves.
        public var bounds: Bounds?

        public struct Bounds: Sendable, Hashable {
            public var minX: Double, minY: Double, maxX: Double, maxY: Double
            public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
                self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
            }
        }

        public init(id: Int, name: String, cancelled: Bool = false, ignored: Bool = false, bounds: Bounds? = nil) {
            self.id = id
            self.name = name
            self.cancelled = cancelled
            self.ignored = ignored
            self.bounds = bounds
        }

        init?(_ json: JSONValue) {
            guard let id = json["id"]?.intValue, let name = json["object"]?.stringValue else { return nil }
            self.id = id
            self.name = name
            cancelled = json["cancelled"]?.boolValue ?? false
            ignored = json["ignore"]?.boolValue ?? false
            if let minX = json["min_x"]?.doubleValue, let maxX = json["max_x"]?.doubleValue,
               let minY = json["min_y"]?.doubleValue, let maxY = json["max_y"]?.doubleValue, maxX >= minX, maxY >= minY {
                bounds = Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
            }
        }

        /// The slicer's label without its file-name noise: "Shape-Box id:0 copy 1" stays readable,
        /// "bin_3x2.stl_id_2_copy_0" becomes "bin 3x2, copy 1".
        public var displayName: String {
            var text = name
            if let match = text.firstMatch(of: /\.(stl|3mf|obj|step)_id_\d+_copy_(\d+)$/.ignoresCase()) {
                let copy = (Int(match.2) ?? 0) + 1
                text = String(text[..<match.range.lowerBound]) + ", copy \(copy)"
            }
            return text.replacingOccurrences(of: "_", with: " ")
        }
    }

    public enum Message: Sendable, Equatable {
        case objects([Object])
        case active(Int?)
    }

    public static func message(_ data: JSONValue) -> Message? {
        if let list = data["objects"]?.arrayValue {
            return .objects(list.compactMap(Object.init))
        }
        if let active = data["ActiveID"] {
            return .active(active.intValue)
        }
        return nil
    }
}

extension OctoPrintClient {
    public func cancelObjectList() async throws -> [CancelObject.Object] {
        let json = try await pluginCommand(CancelObject.pluginID, "objlist")
        return (json["list"]?.arrayValue ?? []).compactMap(CancelObject.Object.init)
    }

    /// Stops printing one object for the rest of the print. This can't be undone.
    public func cancelObject(_ id: Int) async throws {
        _ = try await pluginCommand(CancelObject.pluginID, "cancel", parameters: ["cancelled": JSONValue(id)])
    }
}
