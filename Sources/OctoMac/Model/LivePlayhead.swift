import Foundation
import OctoPrintKit
import QuartzCore

/// Where the nozzle probably is right now, moving smoothly along the toolpath.
///
/// OctoPrint only says how far through the file it has *sent*, a few times a second and in bursts, and the printer
/// works through a queue of moves behind that (Marlin and Prusa firmware hold about 16 to 20). Moves also take longer
/// than their feed rates suggest, because the printer has to speed up and slow down. So the playhead aims a queue's
/// worth of moves behind what's been sent, measures the printer's real pace from how quickly the reports move through
/// the file, averaged over several seconds, and travels steadily at that pace. Each report only nudges it gently, and
/// it never passes what's been sent.
@MainActor
final class LivePlayhead {
    /// Seconds into the print at which each move starts, at its programmed speed.
    private var starts: [Double] = []
    private var durations: [Double] = []
    /// The G-code line each move came from (arcs make several moves from one line).
    private var lines: [Int32] = []
    private var total: Double = 0

    /// The move OctoPrint has sent up to.
    private(set) var target: Int?
    /// Seconds into the print the playhead has reached.
    private var time: Double = 0
    private var lastFrame: TimeInterval?

    /// The print speed factor (M220), 1 = 100%. Only a starting guess: the measured pace takes over.
    var speed: Double = 1 {
        didSet { if pace == nil { measuredPace = speed } }
    }

    /// How many G-code moves the printer holds queued behind what OctoPrint has sent.
    private let queuedMoves = 16
    /// Where the playhead aims: the start of the move a queue's worth behind what's been sent, in print time.
    private var aim: Double = 0

    /// Seconds of programmed print time the printer gets through per real second, averaged.
    private var measuredPace: Double = 1
    private var pace: Double? { lastReport == nil ? nil : measuredPace }
    private var lastReport: (time: TimeInterval, printTime: Double)?

    func load(_ path: GCodeToolpath) {
        starts = []
        durations = []
        starts.reserveCapacity(path.segments.count)
        durations.reserveCapacity(path.segments.count)
        lines = path.segments.map(\.offset)
        var clock = 0.0
        for segment in path.segments {
            starts.append(clock)
            let duration = Double(max(0, segment.duration))
            durations.append(duration)
            clock += duration
        }
        total = clock
        target = nil
        lastFrame = nil
    }

    /// A new report from OctoPrint. Small differences are smoothed out; a big one (opening the preview mid-print,
    /// or a jump backwards) moves straight there.
    func setTarget(_ index: Int?, at now: TimeInterval = CACurrentMediaTime()) {
        guard let index, !starts.isEmpty else {
            target = nil
            lastFrame = nil
            lastReport = nil
            return
        }
        let clamped = min(max(index, 0), starts.count - 1)
        let printTime = starts[clamped]
        let goal = starts[queued(behind: clamped)]
        aim = goal
        if target == nil || abs(goal - time) > 120 {
            time = goal
            lastFrame = nil
            lastReport = nil
            measuredPace = speed
        } else if let last = lastReport, now - last.time > 0.3 {
            // How far the reports moved through the print, per real second, smoothed over the last several reports
            // so bursts of sending even out.
            let sample = (printTime - last.printTime) / (now - last.time)
            if sample >= 0 { measuredPace += (min(4, sample) - measuredPace) * 0.15 }
        }
        if lastReport == nil || now - lastReport!.time > 0.3 { lastReport = (now, printTime) }
        target = clamped
    }

    /// The first move of the G-code line `queuedMoves` lines before `index`.
    private func queued(behind index: Int) -> Int {
        var i = index
        var passed = 0
        while i > 0 && passed < queuedMoves {
            i -= 1
            if lines[i] != lines[i + 1] { passed += 1 }
        }
        while i > 0 && lines[i - 1] == lines[i] { i -= 1 }
        return i
    }

    /// The playhead as a fractional move index (move 12, 40% along), advanced to `now`.
    func position(at now: TimeInterval = CACurrentMediaTime()) -> Double? {
        guard let target, !starts.isEmpty else { return nil }
        let step = min(0.1, max(0, now - (lastFrame ?? now)))
        lastFrame = now
        let sent = starts[target]
        let error = aim - time
        // Steady at the measured pace, gently faster when behind and slower when ahead; never past what's been sent,
        // which the printer can't have passed.
        let rate = max(0.05, measuredPace) * min(1.6, max(0.6, 1 + error / 8))
        time = min(total, sent, time + step * rate)

        var low = 0, high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= time { low = mid } else { high = mid - 1 }
        }
        let fraction = durations[low] > 0 ? min(1, (time - starts[low]) / durations[low]) : 1
        return Double(low) + fraction
    }
}
