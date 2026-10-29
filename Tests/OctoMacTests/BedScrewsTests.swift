import OctoPrintKit
import Testing
@testable import OctoMac

struct BedScrewsTests {
    // Row 0 is the front: front left 0.0, front right +0.1, back left -0.05, back right +0.25.
    let mesh = BedLevelVisualizer.Mesh(z: [[0.0, 0.02, 0.1], [0.01, 0.0, 0.05], [-0.05, 0.1, 0.25]], x: [0, 1, 2], y: [0, 1, 2])

    @Test func readsTheCorners() {
        let corners = BedScrews.heights(of: mesh, at: BedPoint.corners)
        #expect(corners == [.frontLeft: 0.0, .frontRight: 0.1, .backLeft: -0.05, .backRight: 0.25])
    }

    @Test func readsNinePointsFromASevenBySevenMesh() {
        // A Prusa MK3's mesh: the screws sit near rows and columns 0, 3 and 6.
        let z: [[Double?]] = (0..<7).map { row in (0..<7).map { column in Double(row * 10 + column) / 100 } }
        let heights = BedScrews.heights(of: .init(z: z, x: [], y: []), at: BedPoint.allCases)
        #expect(heights.count == 9)
        #expect(heights[.centre] == 0.33)
        #expect(heights[.backRight] == 0.66)
        #expect(heights[.front] == 0.03)
    }

    @Test func turnsEachCornerLevelWithTheFixedOne() throws {
        let settings = BedScrews.Settings(pitch: 0.5, clockwiseLowers: true, fixed: .frontLeft)
        let result = try #require(BedScrews.advice(for: mesh, layout: .corners, settings: settings))
        #expect(result.fixed == .frontLeft)
        let backRight = try #require(result.points[.backRight])
        // 0.25 mm too high: lower it half a turn, clockwise.
        #expect(abs(backRight.change + 0.25) < 0.0001)
        #expect(abs(backRight.turns - 0.5) < 0.0001)
        #expect(backRight.clockwise)
        let backLeft = try #require(result.points[.backLeft])
        #expect(backLeft.change > 0 && !backLeft.clockwise)
        #expect(result.points[.frontLeft]?.isLevel == true)
    }

    @Test func nineScrewsKeepTheCentre() throws {
        let result = try #require(BedScrews.advice(for: mesh, layout: .nine, settings: .init()))
        #expect(result.fixed == .centre)
        #expect(result.points.count == 9)
        // The centre is 0.0 and the back middle +0.1: lower it 0.1 mm, which is 72° of an M3 screw.
        let back = try #require(result.points[.back])
        #expect(BedScrews.degrees(back.turns) == 70)
    }

    @Test func knobsUnderTheBedTurnTheOtherWay() throws {
        let settings = BedScrews.Settings(pitch: 0.5, clockwiseLowers: false, fixed: .frontLeft)
        let result = try #require(BedScrews.advice(for: mesh, layout: .corners, settings: settings))
        #expect(result.points[.backRight]?.clockwise == false)
    }

    @Test func picksTheCornerThatMeansLeastTurning() {
        // Middle two are 0.0 and 0.1; either costs 0.4.
        let heights = BedScrews.heights(of: mesh, at: BedPoint.corners)
        #expect([BedPoint.frontLeft, .frontRight].contains(BedScrews.leastTurning(heights)))
    }

    @Test func guessesTheBedFromWhatItCanSee() {
        #expect(BedScrews.guess(firmware: "Prusa-Firmware 3.14.1+8237 based on Marlin", model: nil, prusaAdjustments: false).layout == .none)
        #expect(BedScrews.guess(firmware: "Marlin 2.1.2.4", model: "Original Prusa MK4", prusaAdjustments: false).layout == .none)
        #expect(BedScrews.guess(firmware: "Prusa-Firmware 3.14.1", model: nil, prusaAdjustments: true).layout == .nine)
        let ender = BedScrews.guess(firmware: "Marlin 2.1.2.4", model: "Creality Ender 3 V3", prusaAdjustments: false)
        #expect(ender.layout == .corners && ender.clue == nil)
    }

    @Test func roundsTurnsToEighths() {
        #expect(BedScrews.turnsText(0.25) == "¼")
        #expect(BedScrews.turnsText(1.5) == "1½")
        #expect(BedScrews.turnsText(0.02) == "0")
        #expect(BedScrews.turnsText(2.0) == "2")
    }

    @Test func needsPointsToWorkFrom() {
        let round = BedLevelVisualizer.Mesh(z: [[nil, 0.1, nil], [0.0, 0.0, 0.0], [nil, 0.1, nil]], x: [0, 1, 2], y: [0, 1, 2])
        #expect(BedScrews.advice(for: round, layout: .corners, settings: .init()) == nil)
    }
}
