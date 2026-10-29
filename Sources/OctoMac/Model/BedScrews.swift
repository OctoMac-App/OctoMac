import Foundation
import OctoPrintKit
import SwiftUI

/// A corner of the bed, where most printers have a levelling screw.
enum BedCorner: String, Codable, CaseIterable, Identifiable {
    case backLeft, backRight, frontLeft, frontRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backLeft: String(localized: "Back left")
        case .backRight: String(localized: "Back right")
        case .frontLeft: String(localized: "Front left")
        case .frontRight: String(localized: "Front right")
        }
    }
}

/// Turns a bed mesh into how far to turn each corner's levelling screw. One corner stays as it is; the others are
/// brought level with it. The mesh's corners stand in for the screws, which sit a little further out on most beds.
enum BedScrews {
    struct Settings: Codable, Equatable {
        /// How far the bed moves for one full turn: 0.5 mm for M3 screws, 0.7 mm for M4, 0.8 mm for M5.
        var pitch = 0.5
        /// Seen from above. True for screws whose heads are on top of the bed; knobs underneath usually work the
        /// other way round.
        var clockwiseLowers = true
        /// The corner to leave alone, or nil to pick the one that means the least turning.
        var fixed: BedCorner?
    }

    struct Advice: Equatable {
        /// How far the corner should move, in mm. Above zero means up.
        var change: Double
        /// Full turns of the screw, always positive.
        var turns: Double
        var clockwise: Bool
        /// Close enough already.
        var isLevel: Bool { abs(change) < tolerance }
    }

    /// Smaller than this isn't worth a turn of the screw.
    static let tolerance = 0.02

    static let pitches: [(pitch: Double, name: String)] = [(0.5, "M3"), (0.7, "M4"), (0.8, "M5")]

    /// The heights at the mesh's four corners. Missing on round beds or patchy meshes.
    static func corners(of mesh: BedLevelVisualizer.Mesh) -> [BedCorner: Double] {
        guard let front = mesh.z.first, let back = mesh.z.last, mesh.z.count > 1 else { return [:] }
        // Row 0 is the front of the bed, column 0 the left.
        let heights: [BedCorner: Double?] = [
            .frontLeft: front.first ?? nil, .frontRight: front.last ?? nil,
            .backLeft: back.first ?? nil, .backRight: back.last ?? nil,
        ]
        return heights.compactMapValues { $0 }
    }

    /// The corner left alone and what to do with each of the others, or nil if the mesh has no corners to go on.
    static func advice(for mesh: BedLevelVisualizer.Mesh, settings: Settings) -> (fixed: BedCorner, corners: [BedCorner: Advice])? {
        let heights = corners(of: mesh)
        guard heights.count >= 3 else { return nil }
        let fixed = settings.fixed.flatMap { heights[$0] != nil ? $0 : nil } ?? leastTurning(heights)
        guard let reference = heights[fixed] else { return nil }
        let corners = heights.mapValues { height -> Advice in
            // A corner that's higher than the reference needs to come down by the difference.
            let change = reference - height
            let turns = abs(change) / settings.pitch
            return Advice(change: change, turns: turns, clockwise: (change < 0) == settings.clockwiseLowers)
        }
        return (fixed, corners)
    }

    /// The corner whose height means the least turning overall: one of the middle two.
    static func leastTurning(_ heights: [BedCorner: Double]) -> BedCorner {
        let order = BedCorner.allCases.filter { heights[$0] != nil }
        return order.min { a, b in
            let costA = heights.values.reduce(0) { $0 + abs($1 - heights[a]!) }
            let costB = heights.values.reduce(0) { $0 + abs($1 - heights[b]!) }
            return costA < costB
        } ?? .frontLeft
    }

    /// Turns as a friendly fraction, to the nearest eighth: "¼", "1½", "2".
    static func turnsText(_ turns: Double) -> String {
        let eighths = Int((turns * 8).rounded())
        let whole = eighths / 8
        let fraction = ["", "⅛", "¼", "⅜", "½", "⅝", "¾", "⅞"][eighths % 8]
        if whole == 0 { return fraction.isEmpty ? "0" : fraction }
        return "\(whole.formatted())\(fraction)"
    }
}
