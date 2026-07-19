import Foundation
import Testing
@testable import OctoPrintKit

/// Parses a real slicer file when `OCTO_GCODE` points at one; otherwise skipped.
struct GCodeRealFileTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OCTO_GCODE"] != nil))
    func realFile() throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OCTO_GCODE"]!)
        let data = try Data(contentsOf: url)
        let start = Date.now
        let path = GCodeParser.parse(data)
        let elapsed = Date.now.timeIntervalSince(start)
        let counts = Dictionary(grouping: path.segments, by: \.feature).mapValues(\.count)
        print("REAL: \(data.count) bytes, \(path.lineCount) lines, \(path.layers.count) layers, \(path.segments.count) segments in \(String(format: "%.3f", elapsed))s")
        print("REAL: first z \(path.layers.first?.z ?? -1), last z \(path.layers.last?.z ?? -1), bounds \(String(describing: path.bounds))")
        print("REAL: features \(counts.sorted { $0.value > $1.value }.map { "\($0.key.displayName)=\($0.value)" }.joined(separator: ", "))")
        #expect(!path.layers.isEmpty)
    }
}
