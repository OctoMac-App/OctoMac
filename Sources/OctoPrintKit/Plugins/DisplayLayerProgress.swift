import Foundation

/// Support for the DisplayLayerProgress plugin (https://github.com/OllisGit/OctoPrint-DisplayLayerProgress).
///
/// The plugin reads the slicer's layer markers as the file prints, so it knows the real layer number and the
/// layer count. It pushes `{"plugin": "DisplayLayerProgress-websocket-payload", "data": {...}}` on every layer
/// change, and `GET /plugin/DisplayLayerProgress/values` returns the same facts on demand.
/// Values it doesn't know yet are sent as "-".
public struct LayerProgress: Sendable, Hashable {
    public static let pluginID = "DisplayLayerProgress"
    public static let pushID = "DisplayLayerProgress-websocket-payload"

    public var currentLayer: Int?
    public var totalLayers: Int?
    public var currentHeight: Double?
    public var totalHeight: Double?
    /// Seconds.
    public var lastLayerDuration: Double?
    public var averageLayerDuration: Double?
    /// Filament changes (M600) still to come in this print.
    public var filamentChangesLeft: Int?
    /// Seconds until the next filament change.
    public var nextFilamentChangeIn: Double?

    /// Parses the push payload (flat keys).
    public init(push data: JSONValue) {
        currentLayer = Self.int(data["currentLayer"])
        totalLayers = Self.int(data["totalLayer"])
        currentHeight = Self.number(data["currentHeight"])
        totalHeight = Self.number(data["totalHeight"])
        lastLayerDuration = Self.number(data["lastLayerDurationInSeconds"])
        averageLayerDuration = Self.number(data["averageLayerDurationInSeconds"])
        filamentChangesLeft = Self.int(data["changeFilamentCount"])
        nextFilamentChangeIn = Self.number(data["changeFilamentTimeLeftInSeconds"])
    }

    /// Parses `GET /plugin/DisplayLayerProgress/values` (nested keys).
    public init(values data: JSONValue) {
        currentLayer = Self.int(data.value(at: "layer", "current"))
        totalLayers = Self.int(data.value(at: "layer", "total"))
        currentHeight = Self.number(data.value(at: "height", "current"))
        totalHeight = Self.number(data.value(at: "height", "total"))
        lastLayerDuration = Self.number(data.value(at: "layer", "lastLayerDurationInSeconds"))
        averageLayerDuration = Self.number(data.value(at: "layer", "averageLayerDurationInSeconds"))
        filamentChangesLeft = Self.int(data.value(at: "print", "changeFilamentCount"))
        nextFilamentChangeIn = Self.number(data.value(at: "print", "changeFilamentTimeLeftInSeconds"))
    }

    public init(currentLayer: Int?, totalLayers: Int?, averageLayerDuration: Double? = nil, lastLayerDuration: Double? = nil) {
        self.currentLayer = currentLayer
        self.totalLayers = totalLayers
        self.averageLayerDuration = averageLayerDuration
        self.lastLayerDuration = lastLayerDuration
    }

    /// True once the plugin has a layer count for the current print.
    public var hasLayers: Bool { (totalLayers ?? 0) > 0 && currentLayer != nil }

    private static func number(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        if let string = value.stringValue {
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed == "-" ? nil : Double(trimmed)
        }
        return value.doubleValue
    }

    private static func int(_ value: JSONValue?) -> Int? { number(value).map { Int($0) } }
}

extension OctoPrintClient {
    public func layerProgress() async throws -> LayerProgress {
        let json: JSONValue = try await get("plugin/\(LayerProgress.pluginID)/values")
        return LayerProgress(values: json)
    }
}
