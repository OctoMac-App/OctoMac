import Foundation
import OctoPrintKit
import SwiftUI

/// A point on the bed where a screw can be: the corners, the middle of each edge, and the centre.
enum BedPoint: String, Codable, CaseIterable, Identifiable {
    // The raw values of the corners predate the other points, and are kept so saved settings still read.
    case backLeft, back, backRight, left, centre, right, frontLeft, front, frontRight

    var id: String { rawValue }

    static let corners: [BedPoint] = [.backLeft, .backRight, .frontLeft, .frontRight]

    var title: String {
        switch self {
        case .backLeft: String(localized: "Back left")
        case .back: String(localized: "Back middle")
        case .backRight: String(localized: "Back right")
        case .left: String(localized: "Left middle")
        case .centre: String(localized: "Centre")
        case .right: String(localized: "Right middle")
        case .frontLeft: String(localized: "Front left")
        case .front: String(localized: "Front middle")
        case .frontRight: String(localized: "Front right")
        }
    }

    /// Where on the bed, from 0 to 2 across (left to right) and up (front to back).
    var grid: (column: Int, row: Int) {
        switch self {
        case .frontLeft: (0, 0)
        case .front: (1, 0)
        case .frontRight: (2, 0)
        case .left: (0, 1)
        case .centre: (1, 1)
        case .right: (2, 1)
        case .backLeft: (0, 2)
        case .back: (1, 2)
        case .backRight: (2, 2)
        }
    }
}

/// Turns a bed mesh into how far to turn each levelling screw. One screw stays as it is; the others are brought level
/// with it. The mesh's measured points stand in for the screws, which sit a little further out on most beds.
enum BedScrews {
    /// How the bed is held.
    enum Layout: String, Codable, CaseIterable {
        /// A screw or knob at each corner: most printers.
        case corners
        /// Nine screws in a 3 × 3 grid, adjustable after the "nylock mod" on a Prusa MK3.
        case nine
        /// Nothing to adjust: the printer measures the bed before every print and allows for its shape (a stock Prusa).
        case none

        var points: [BedPoint] {
            switch self {
            case .corners: BedPoint.corners
            case .nine: BedPoint.allCases
            case .none: []
            }
        }
    }

    struct Settings: Codable, Equatable {
        /// How far the bed moves for one full turn: 0.5 mm for M3 screws, 0.7 mm for M4, 0.8 mm for M5.
        var pitch = 0.5
        /// Seen from above. True for screws whose heads are on top of the bed; knobs underneath usually work the
        /// other way round.
        var clockwiseLowers = true
        /// The screw to leave alone, or nil for the usual one: the centre of nine, or whichever corner means least turning.
        var fixed: BedPoint?
        /// Nil until chosen; until then OctoMac guesses from the firmware and printer profile.
        var layout: Layout?
    }

    struct Advice: Equatable {
        /// How far the point should move, in mm. Above zero means up.
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

    /// A best guess at the layout, and the clue it came from, for a printer you haven't told OctoMac about.
    static func guess(firmware: String?, model: String?, prusaAdjustments: Bool) -> (layout: Layout, clue: String?) {
        if prusaAdjustments { return (.nine, String(localized: "Bed Visualizer is set up for Prusa adjustments")) }
        // Prusa's firmware (MK3 family, and Buddy on the MK4, MINI and XL) measures the bed and allows for it.
        if let firmware, firmware.localizedCaseInsensitiveContains("Prusa") {
            return (.none, MachinePage.shortFirmware(firmware))
        }
        if let model, ["Prusa", "MK3", "MK4", "MINI", "XL"].contains(where: { model.localizedCaseInsensitiveContains($0) }) {
            return (.none, model)
        }
        return (.corners, nil)
    }

    /// The heights at the given points of the mesh: its corners, edge middles and centre. Missing on round beds or
    /// patchy meshes.
    static func heights(of mesh: BedLevelVisualizer.Mesh, at points: [BedPoint]) -> [BedPoint: Double] {
        let rows = mesh.z.count, columns = mesh.z.first?.count ?? 0
        guard rows > 1, columns > 1 else { return [:] }
        // Row 0 is the front of the bed, column 0 the left. A 7 × 7 mesh gives rows and columns 0, 3 and 6.
        func index(_ step: Int, of count: Int) -> Int { [0, (count - 1) / 2, count - 1][step] }
        var result: [BedPoint: Double] = [:]
        for point in points {
            let row = index(point.grid.row, of: rows), column = index(point.grid.column, of: columns)
            if mesh.z[row].indices.contains(column), let height = mesh.z[row][column] { result[point] = height }
        }
        return result
    }

    /// The point left alone and what to do with each of the others, or nil if the mesh doesn't reach enough of them.
    static func advice(for mesh: BedLevelVisualizer.Mesh, layout: Layout, settings: Settings)
        -> (fixed: BedPoint, points: [BedPoint: Advice])? {
        let heights = heights(of: mesh, at: layout.points)
        guard heights.count >= 3 else { return nil }
        let preferred = settings.fixed ?? (layout == .nine ? .centre : nil)
        let fixed = preferred.flatMap { heights[$0] != nil ? $0 : nil } ?? leastTurning(heights)
        guard let reference = heights[fixed] else { return nil }
        let points = heights.mapValues { height -> Advice in
            // A point that's higher than the reference needs to come down by the difference.
            let change = reference - height
            let turns = abs(change) / settings.pitch
            return Advice(change: change, turns: turns, clockwise: (change < 0) == settings.clockwiseLowers)
        }
        return (fixed, points)
    }

    /// The point whose height means the least turning overall.
    static func leastTurning(_ heights: [BedPoint: Double]) -> BedPoint {
        let order = BedPoint.allCases.filter { heights[$0] != nil }
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

    /// Turns as degrees, to the nearest 5°, for the small adjustments of a nine-screw bed: 0.05 mm is 36°.
    static func degrees(_ turns: Double) -> Int {
        Int((turns * 360 / 5).rounded()) * 5
    }
}
