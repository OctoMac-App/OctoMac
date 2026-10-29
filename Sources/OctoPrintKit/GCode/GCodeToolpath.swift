import Foundation

/// A G-code file reduced to the moves needed to draw it, grouped into layers.
public struct GCodeToolpath: Sendable {
    /// What a move is printing, from the slicer's `;TYPE:` (PrusaSlicer, Cura) or `;FEATURE:` (Orca, Bambu) comments.
    public enum Feature: UInt8, CaseIterable, Sendable, Hashable {
        case outerWall, innerWall, overhangWall, solidInfill, topSolidInfill, sparseInfill, bridgeInfill, gapFill,
             skirt, support, supportInterface, wipeTower, ironing, custom, other, travel

        public var displayName: String {
            switch self {
            case .outerWall: String(localized: "Outer wall", comment: "A kind of move in sliced G-code")
            case .innerWall: String(localized: "Inner wall", comment: "A kind of move in sliced G-code")
            case .overhangWall: String(localized: "Overhang wall", comment: "A kind of move in sliced G-code")
            case .solidInfill: String(localized: "Solid infill", comment: "A kind of move in sliced G-code")
            case .topSolidInfill: String(localized: "Top surface", comment: "A kind of move in sliced G-code")
            case .sparseInfill: String(localized: "Infill", comment: "A kind of move in sliced G-code")
            case .bridgeInfill: String(localized: "Bridge", comment: "A kind of move in sliced G-code")
            case .gapFill: String(localized: "Gap fill", comment: "A kind of move in sliced G-code")
            case .skirt: String(localized: "Skirt / brim", comment: "A kind of move in sliced G-code")
            case .support: String(localized: "Support", comment: "A kind of move in sliced G-code")
            case .supportInterface: String(localized: "Support interface", comment: "A kind of move in sliced G-code")
            case .wipeTower: String(localized: "Wipe tower", comment: "A kind of move in sliced G-code")
            case .ironing: String(localized: "Ironing", comment: "A kind of move in sliced G-code")
            case .custom: String(localized: "Custom", comment: "A kind of move in sliced G-code")
            case .other: String(localized: "Other", comment: "A kind of move in sliced G-code")
            case .travel: String(localized: "Travel", comment: "A kind of move in sliced G-code")
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
        /// Byte offset of the G-code line that made this move.
        public var offset: Int32
        /// How long the move takes at its programmed feed rate, in seconds (acceleration ignored).
        public var duration: Float = 0
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

    /// The move being made at a byte position in the file (the last move starting at or before it).
    public func segmentIndex(atFileOffset offset: Int) -> Int? {
        guard !segments.isEmpty, offset >= Int(segments[0].offset) else { return segments.isEmpty ? nil : 0 }
        var low = 0, high = segments.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if Int(segments[mid].offset) <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// The layer a move belongs to.
    public func layerIndex(ofSegment index: Int) -> Int? {
        guard !layers.isEmpty else { return nil }
        var low = 0, high = layers.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if layers[mid].segments.lowerBound <= index { low = mid } else { high = mid - 1 }
        }
        return low
    }

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
