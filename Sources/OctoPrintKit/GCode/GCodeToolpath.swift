import Foundation

/// A G-code file reduced to the moves needed to draw it, grouped into layers.
public struct GCodeToolpath: Sendable {
    /// What a move is printing, from the slicer's `;TYPE:` (PrusaSlicer, Cura) or `;FEATURE:` (Orca, Bambu) comments.
    public enum Feature: UInt8, CaseIterable, Sendable, Hashable {
        case outerWall, innerWall, overhangWall, solidInfill, topSolidInfill, sparseInfill, bridgeInfill, gapFill,
             skirt, support, supportInterface, wipeTower, ironing, custom, other, travel

        public var displayName: String {
            switch self {
            case .outerWall: "Outer wall"
            case .innerWall: "Inner wall"
            case .overhangWall: "Overhang wall"
            case .solidInfill: "Solid infill"
            case .topSolidInfill: "Top surface"
            case .sparseInfill: "Infill"
            case .bridgeInfill: "Bridge"
            case .gapFill: "Gap fill"
            case .skirt: "Skirt / brim"
            case .support: "Support"
            case .supportInterface: "Support interface"
            case .wipeTower: "Wipe tower"
            case .ironing: "Ironing"
            case .custom: "Custom"
            case .other: "Other"
            case .travel: "Travel"
            }
        }

        /// Maps a slicer's feature label to a feature.
        public init(label raw: String) {
            let label = raw.trimmingCharacters(in: .whitespaces).lowercased()
            switch label {
            case "external perimeter", "wall-outer", "outer wall": self = .outerWall
            case "perimeter", "wall-inner", "inner wall": self = .innerWall
            case "overhang perimeter", "overhang wall": self = .overhangWall
            case "solid infill", "internal solid infill", "skin", "bottom surface": self = .solidInfill
            case "top solid infill", "top surface": self = .topSolidInfill
            case "internal infill", "fill", "sparse infill": self = .sparseInfill
            case "bridge infill", "internal bridge", "bridge": self = .bridgeInfill
            case "gap fill", "gap infill": self = .gapFill
            case "skirt/brim", "skirt", "brim": self = .skirt
            case "support material", "support": self = .support
            case "support material interface", "support interface", "support-interface": self = .supportInterface
            case "wipe tower", "prime tower": self = .wipeTower
            case "ironing": self = .ironing
            case "custom": self = .custom
            default: self = .other
            }
        }
    }

    public struct Segment: Sendable {
        public var x0: Float, y0: Float, x1: Float, y1: Float
        public var feature: Feature
    }

    public struct Layer: Sendable {
        /// Height of the extrusions in this layer (mm).
        public var z: Float
        /// Index range into `segments`.
        public var segments: Range<Int>
        /// Byte offset in the file where the layer's first extrusion starts (for matching print progress).
        public var fileOffset: Int
    }

    public var segments: [Segment] = []
    public var layers: [Layer] = []
    /// Extent of the extrusions on the bed (mm), or nil for a file with no printing moves.
    public var bounds: (minX: Float, minY: Float, maxX: Float, maxY: Float)?
    public var lineCount = 0
    public var byteCount = 0

    public init() {}

    public func segments(in layer: Layer) -> ArraySlice<Segment> { segments[layer.segments] }

    /// The layer being printed at a byte position in the file (e.g. OctoPrint's `progress.filepos`).
    public func layerIndex(atFileOffset offset: Int) -> Int? {
        guard !layers.isEmpty else { return nil }
        var low = 0, high = layers.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if layers[mid].fileOffset <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }
}
