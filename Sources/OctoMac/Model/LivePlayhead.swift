import Foundation
import OctoPrintKit
import QuartzCore

/// Where the nozzle probably is right now, moving smoothly along the toolpath.
///
/// OctoPrint only says how far through the file it has *sent*, a few times a second and in bursts, and the printer
/// works through a small buffer behind that. So instead of jumping to each report, the playhead travels along the
/// moves in real time at their own feed rates (times the print speed), and each report only nudges its pace:
/// a little faster when it's falling behind, slower when it gets too close to what's been sent.
@MainActor
final class LivePlayhead {
    /// Seconds into the print at which each move starts, at its programmed speed.
    private var starts: [Double] = []
    private var durations: [Double] = []
    private var total: Double = 0

    /// The move OctoPrint has sent up to.
    private(set) var target: Int?
    /// Seconds into the print the playhead has reached.
    private var time: Double = 0
    private var lastFrame: TimeInterval?

    /// The print speed factor (M220), 1 = 100%.
    var speed: Double = 1

    /// How far behind what OctoPrint has sent the printer usually is: its buffer of queued moves.
    private let lead: Double = 1.5

    func load(_ path: GCodeToolpath) {
        starts = []
        durations = []
        starts.reserveCapacity(path.segments.count)
        durations.reserveCapacity(path.segments.count)
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
    func setTarget(_ index: Int?) {
        guard let index, !starts.isEmpty else {
            target = nil
            lastFrame = nil
            return
        }
        let clamped = min(max(index, 0), starts.count - 1)
        let goal = max(0, starts[clamped] - lead)
        if target == nil || abs(goal - time) > 45 {
            time = goal
            lastFrame = nil
        }
        target = clamped
    }

    /// The playhead as a fractional move index (move 12, 40% along), advanced to `now`.
    func position(at now: TimeInterval = CACurrentMediaTime()) -> Double? {
        guard let target, !starts.isEmpty else { return nil }
        let step = min(0.1, max(0, now - (lastFrame ?? now)))
        lastFrame = now
        let error = max(0, starts[target] - lead) - time
        // On pace when on target, up to four times faster when behind, and easing to a stop by the time it reaches
        // what OctoPrint has sent, which the printer can't have passed.
        let rate = speed * min(4, max(0, 1 + error / lead))
        time = min(total, time + step * rate)

        var low = 0, high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= time { low = mid } else { high = mid - 1 }
        }
        let fraction = durations[low] > 0 ? min(1, (time - starts[low]) / durations[low]) : 1
        return Double(low) + fraction
    }
}
