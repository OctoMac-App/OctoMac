import Foundation
import Testing
@testable import OctoPrintKit

struct GCodeParserTests {
    private func parse(_ text: String) -> GCodeToolpath { GCodeParser.parse(Data(text.utf8)) }

    @Test func layersFeaturesAndTravel() {
        let path = parse("""
        M83
        G1 Z0.2 F600
        ;TYPE:External perimeter
        G1 X10 Y0 E1
        G1 X10 Y10 E1
        G1 X20 Y10        ; travel
        ;TYPE:Internal infill
        G1 X30 Y10 E.5
        G1 Z0.6           ; z-hop, no new layer
        G1 X0 Y0
        G1 Z0.4
        ;TYPE:Perimeter
        G1 X5 Y0 E.2
        """)
        #expect(path.layers.count == 2)
        #expect(path.layers[0].z == 0.2)
        #expect(path.layers[1].z == 0.4)
        let first = path.segments(in: path.layers[0]).map(\.feature)
        #expect(first == [.outerWall, .outerWall, .travel, .sparseInfill, .travel])
        #expect(path.segments(in: path.layers[1]).map(\.feature) == [.innerWall])
        #expect(path.bounds?.maxX == 30)
    }

    @Test func absoluteExtrusionAndReset() {
        let path = parse("""
        M82
        G1 Z0.2
        G1 X10 E1
        G1 X20 E0.5     ; retracting, so not printing
        G92 E0
        G1 X30 E1
        """)
        #expect(path.segments.map(\.feature) == [.other, .travel, .other])
    }

    @Test func arcsAreInterpolated() {
        let path = parse("""
        M83
        G1 Z0.2
        G1 X10 Y0
        G3 X-10 Y0 I-10 J0 E2
        """)
        let arc = path.segments.filter { $0.feature != .travel }
        #expect(arc.count > 10)
        #expect(abs((arc.last?.x1 ?? 0) + 10) < 0.001)
        // A counter-clockwise half circle from (10,0) to (-10,0) passes through the top.
        #expect((arc.map(\.y1).max() ?? 0) > 9.9)
    }

    @Test func layerForFileOffset() {
        let text = "M83\nG1 Z0.2\nG1 X1 E1\nG1 Z0.4\nG1 X2 E1\nG1 Z0.6\nG1 X3 E1\n"
        let path = parse(text)
        #expect(path.layers.count == 3)
        let secondLayerOffset = path.layers[1].fileOffset
        #expect(path.layerIndex(atFileOffset: secondLayerOffset + 1) == 1)
        #expect(path.layerIndex(atFileOffset: text.utf8.count) == 2)
    }

    @Test func moveForFileOffset() {
        let text = "M83\nG1 Z0.2\nG1 X1 E1\nG1 X2 E1\nG1 Z0.4\nG1 X3 E1\n"
        let path = parse(text)
        let offsets = path.segments.map(\.offset)
        #expect(offsets == offsets.sorted())
        // Halfway into the "G1 X2" line is still the second move.
        let second = Int(path.segments[1].offset)
        #expect(path.segmentIndex(atFileOffset: second + 3) == 1)
        #expect(path.layerIndex(ofSegment: 2) == 1)
        #expect(path.segmentIndex(atFileOffset: 0) == 0)
    }

    @Test func featureLabelsFromSeveralSlicers() {
        #expect(GCodeToolpath.Feature(label: "WALL-OUTER") == .outerWall)       // Cura
        #expect(GCodeToolpath.Feature(label: " Outer wall") == .outerWall)      // Orca / Bambu
        #expect(GCodeToolpath.Feature(label: "Top solid infill") == .topSolidInfill)
        #expect(GCodeToolpath.Feature(label: "something new") == .other)
    }
}
