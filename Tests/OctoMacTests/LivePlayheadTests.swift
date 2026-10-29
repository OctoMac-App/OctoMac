import Foundation
@testable import OctoPrintKit
import Testing
@testable import OctoMac

@MainActor
struct LivePlayheadTests {
    /// Ten moves of one second each.
    private func path() -> GCodeToolpath {
        var path = GCodeToolpath()
        path.segments = (0..<10).map { i in
            GCodeToolpath.Segment(x0: Float(i), y0: 0, x1: Float(i + 1), y1: 0, feature: .outerWall, offset: Int32(i * 10), duration: 1)
        }
        return path
    }

    @Test func glidesInRealTimeAndNeverPassesWhatWasSent() throws {
        let playhead = LivePlayhead()
        playhead.load(path())
        playhead.setTarget(6)
        // Opening mid-print starts just behind what's been sent.
        let start = try #require(playhead.position(at: 100))
        #expect(abs(start - 4.5) < 0.001)
        // Moves on smoothly, at about the printer's pace.
        let later = try #require(playhead.position(at: 100.1))
        #expect(later > start && later < start + 0.2)
        // With no new report it slows down and stops at the sent move rather than running past it.
        var now = 100.1
        var position = later
        for _ in 0..<600 { now += 1.0 / 30; position = try #require(playhead.position(at: now)) }
        #expect(position <= 6.001)
        #expect(position > 5.5)
    }

    @Test func farJumpsMoveStraightThere() throws {
        let playhead = LivePlayhead()
        playhead.load(path())
        playhead.setTarget(1)
        _ = playhead.position(at: 0)
        playhead.setTarget(9)
        let position = try #require(playhead.position(at: 0.05))
        #expect(position > 0 && position < 9)
    }
}
