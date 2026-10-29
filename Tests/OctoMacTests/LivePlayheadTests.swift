import Foundation
@testable import OctoPrintKit
import Testing
@testable import OctoMac

@MainActor
struct LivePlayheadTests {
    /// Forty moves of one second each, one per G-code line.
    private func path() -> GCodeToolpath {
        var path = GCodeToolpath()
        path.segments = (0..<40).map { i in
            GCodeToolpath.Segment(x0: Float(i), y0: 0, x1: Float(i + 1), y1: 0, feature: .outerWall, offset: Int32(i * 10), duration: 1)
        }
        return path
    }

    @Test func glidesInRealTimeAndNeverPassesWhatWasSent() throws {
        let playhead = LivePlayhead()
        playhead.load(path())
        playhead.setTarget(30, at: 100)
        // Opening mid-print starts a printer's queue of moves (20) behind what's been sent.
        let start = try #require(playhead.position(at: 100))
        #expect(abs(start - 10) < 0.001)
        // Moves on smoothly, at about the printer's pace.
        let later = try #require(playhead.position(at: 100.1))
        #expect(later > start && later < start + 0.2)
        // With no new report it slows down and stops at the sent move rather than running past it.
        var now = 100.1
        var position = later
        for _ in 0..<3000 { now += 1.0 / 30; position = try #require(playhead.position(at: now)) }
        #expect(position <= 30.001)
        #expect(position > 29.5)
    }

    @Test func keepsAnEvenPaceThroughBurstyReports() throws {
        var path = GCodeToolpath()
        path.segments = (0..<400).map { i in
            GCodeToolpath.Segment(x0: Float(i), y0: 0, x1: Float(i + 1), y1: 0, feature: .outerWall, offset: Int32(i * 10), duration: 1)
        }
        let playhead = LivePlayhead()
        playhead.load(path)
        // The printer really manages half the programmed speed, and OctoPrint reports in bursts every 2 seconds.
        var now = 0.0
        var steps: [Double] = []
        var previous: Double?
        for frame in 0..<(60 * 30) {
            if frame % 60 == 0 { playhead.setTarget(30 + Int(now * 0.5), at: now) }
            let position = try #require(playhead.position(at: now))
            if let previous, frame > 30 * 30 { steps.append(position - previous) }
            previous = position
            now += 1.0 / 30
        }
        // Once it has the measure of the printer, it moves at an even pace rather than dashing and stopping.
        let fastest = try #require(steps.max()), slowest = try #require(steps.min())
        #expect(slowest > 0)
        #expect(fastest / slowest < 1.6)
    }

    @Test func arcsCountAsOneQueuedLine() throws {
        // Every G-code line here is an arc split into four moves; the printer queues lines, not split moves.
        var path = GCodeToolpath()
        for i in 0..<200 {
            let line = Int32(i / 4) * 10
            path.segments.append(GCodeToolpath.Segment(x0: Float(i), y0: 0, x1: Float(i + 1), y1: 0, feature: .outerWall,
                                                       offset: line, duration: 0.25))
        }
        let playhead = LivePlayhead()
        playhead.load(path)
        playhead.setTarget(150, at: 0)
        let start = try #require(playhead.position(at: 0))
        // Move 150 is on line 37; twenty lines back is line 17, whose first move is 68.
        #expect(abs(start - 68) < 0.001)
    }

    @Test func farJumpsMoveStraightThere() throws {
        let playhead = LivePlayhead()
        playhead.load(path())
        playhead.setTarget(1)
        _ = playhead.position(at: 0)
        playhead.setTarget(39)
        let position = try #require(playhead.position(at: 0.05))
        #expect(position > 0 && position < 39)
    }
}
