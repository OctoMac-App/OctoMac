import OctoPrintKit
import Testing
@testable import OctoMac

struct BedScrewsTests {
    // Row 0 is the front: front left 0.0, front right +0.1, back left -0.05, back right +0.25.
    let mesh = BedLevelVisualizer.Mesh(z: [[0.0, 0.02, 0.1], [0.01, 0.0, 0.05], [-0.05, 0.1, 0.25]], x: [0, 1, 2], y: [0, 1, 2])

    @Test func readsTheCorners() {
        let corners = BedScrews.corners(of: mesh)
        #expect(corners == [.frontLeft: 0.0, .frontRight: 0.1, .backLeft: -0.05, .backRight: 0.25])
    }

    @Test func turnsEachCornerLevelWithTheFixedOne() throws {
        let settings = BedScrews.Settings(pitch: 0.5, clockwiseLowers: true, fixed: .frontLeft)
        let result = try #require(BedScrews.advice(for: mesh, settings: settings))
        #expect(result.fixed == .frontLeft)
        let backRight = try #require(result.corners[.backRight])
        // 0.25 mm too high: lower it half a turn, clockwise.
        #expect(abs(backRight.change + 0.25) < 0.0001)
        #expect(abs(backRight.turns - 0.5) < 0.0001)
        #expect(backRight.clockwise)
        let backLeft = try #require(result.corners[.backLeft])
        #expect(backLeft.change > 0 && !backLeft.clockwise)
        #expect(result.corners[.frontLeft]?.isLevel == true)
    }

    @Test func knobsUnderTheBedTurnTheOtherWay() throws {
        let settings = BedScrews.Settings(pitch: 0.5, clockwiseLowers: false, fixed: .frontLeft)
        let result = try #require(BedScrews.advice(for: mesh, settings: settings))
        #expect(result.corners[.backRight]?.clockwise == false)
    }

    @Test func picksTheCornerThatMeansLeastTurning() {
        // Middle two are 0.0 and 0.1; either costs 0.4, and front left comes first among them.
        #expect([BedCorner.frontLeft, .frontRight].contains(BedScrews.leastTurning(BedScrews.corners(of: mesh))))
    }

    @Test func roundsTurnsToEighths() {
        #expect(BedScrews.turnsText(0.25) == "¼")
        #expect(BedScrews.turnsText(1.5) == "1½")
        #expect(BedScrews.turnsText(0.02) == "0")
        #expect(BedScrews.turnsText(2.0) == "2")
    }

    @Test func needsCornersToWorkFrom() {
        let round = BedLevelVisualizer.Mesh(z: [[nil, 0.1, nil], [0.0, 0.0, 0.0], [nil, 0.1, nil]], x: [0, 1, 2], y: [0, 1, 2])
        #expect(BedScrews.advice(for: round, settings: .init()) == nil)
    }
}
