import Foundation

/// Reads G-code into a `GCodeToolpath`.
///
/// Understands G0/G1 moves, G2/G3 arcs (I/J form), absolute/relative positioning (G90/G91), absolute/relative
/// extrusion (M82/M83), G92 position resets and G28 homing. Layers are started whenever extrusion happens at a new
/// height, which works for every slicer and isn't fooled by Z-hops (those are travel moves).
/// Scans raw bytes rather than building strings per line, so multi-megabyte files parse in well under a second.
public enum GCodeParser {
    public static func parse(_ data: Data, progress: (@Sendable (Double) -> Void)? = nil) -> GCodeToolpath {
        var state = State()
        state.path.byteCount = data.count
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let bytes = buffer.bindMemory(to: UInt8.self)
            let count = bytes.count
            var lineStart = 0
            var nextProgress = 1 << 20
            while lineStart < count {
                var lineEnd = lineStart
                while lineEnd < count && bytes[lineEnd] != 0x0A { lineEnd += 1 }
                state.parseLine(bytes, lineStart, lineEnd)
                state.path.lineCount += 1
                lineStart = lineEnd + 1
                if lineStart >= nextProgress {
                    progress?(Double(lineStart) / Double(count))
                    nextProgress += 1 << 20
                }
            }
        }
        state.finishLayer()
        progress?(1)
        return state.path
    }

    private struct State {
        var path = GCodeToolpath()
        var x: Double = 0, y: Double = 0, z: Double = 0, e: Double = 0
        /// Current feed rate in mm/min (G-code's F is modal).
        var feedRate: Double = 1500
        var relativeXYZ = false
        var relativeE = false
        var feature: GCodeToolpath.Feature = .other

        var layerZ: Double?
        var layerStart = 0
        var layerOffset = 0
        var minX = Float.infinity, minY = Float.infinity, maxX = -Float.infinity, maxY = -Float.infinity

        mutating func parseLine(_ b: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) {
            var i = start
            while i < end && (b[i] == 0x20 || b[i] == 0x09) { i += 1 }
            guard i < end else { return }

            if b[i] == 0x3B { // ';' comment
                parseComment(b, i + 1, end)
                return
            }

            let letter = b[i] | 0x20 // lowercase
            guard letter == 0x67 || letter == 0x6D else { return } // 'g' or 'm'
            i += 1
            var code = 0
            while i < end, b[i] >= 0x30, b[i] <= 0x39 { code = code * 10 + Int(b[i] - 0x30); i += 1 }

            // Parameters up to an inline comment.
            var px: Double?, py: Double?, pz: Double?, pe: Double?, pi: Double?, pj: Double?, pf: Double?
            while i < end && b[i] != 0x3B {
                let c = b[i] | 0x20
                i += 1
                guard c >= 0x61 && c <= 0x7A else { continue }
                let (value, next) = number(b, i, end)
                i = next
                guard let value else { continue }
                switch c {
                case 0x78: px = value // x
                case 0x79: py = value // y
                case 0x7A: pz = value // z
                case 0x65: pe = value // e
                case 0x69: pi = value // i
                case 0x6A: pj = value // j
                case 0x66: pf = value // f
                default: break
                }
            }

            if letter == 0x67 { // G
                if let pf, pf > 0, code <= 3 { feedRate = pf }
                switch code {
                case 0, 1: move(px, py, pz, pe, offset: start)
                case 2, 3: arc(clockwise: code == 2, px, py, pz, pe, pi, pj, offset: start)
                case 28:
                    let all = px == nil && py == nil && pz == nil
                    if all || px != nil { x = 0 }
                    if all || py != nil { y = 0 }
                    if all || pz != nil { z = 0 }
                case 90: relativeXYZ = false; relativeE = false
                case 91: relativeXYZ = true; relativeE = true
                case 92:
                    if let px { x = px }
                    if let py { y = py }
                    if let pz { z = pz }
                    if let pe { e = pe }
                default: break
                }
            } else { // M
                switch code {
                case 82: relativeE = false
                case 83: relativeE = true
                default: break
                }
            }
        }

        mutating func parseComment(_ b: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) {
            // Only ";TYPE:..." and ";FEATURE: ..." matter; check the first bytes before making a string.
            var i = start
            while i < end && b[i] == 0x20 { i += 1 }
            func has(_ prefix: StaticString) -> Bool {
                let n = prefix.utf8CodeUnitCount
                guard end - i >= n else { return false }
                let p = prefix.utf8Start
                for k in 0..<n where (b[i + k] | 0x20) != (p[k] | 0x20) { return false }
                return true
            }
            let skip: Int
            if has("TYPE:") { skip = 5 } else if has("FEATURE:") { skip = 8 } else { return }
            let labelStart = i + skip
            var labelEnd = end
            while labelEnd > labelStart && (b[labelEnd - 1] == 0x0D || b[labelEnd - 1] == 0x20) { labelEnd -= 1 }
            let label = String(decoding: UnsafeBufferPointer(rebasing: b[labelStart..<labelEnd]), as: UTF8.self)
            feature = GCodeToolpath.Feature(label: label)
        }

        /// Parses a decimal number such as `-12.5` or `.02` starting at `i`.
        func number(_ b: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> (Double?, Int) {
            var i = start
            var negative = false
            if i < end && (b[i] == 0x2D || b[i] == 0x2B) { negative = b[i] == 0x2D; i += 1 }
            var value: Double = 0
            var digits = 0
            while i < end, b[i] >= 0x30, b[i] <= 0x39 { value = value * 10 + Double(b[i] - 0x30); i += 1; digits += 1 }
            if i < end && b[i] == 0x2E {
                i += 1
                var scale = 0.1
                while i < end, b[i] >= 0x30, b[i] <= 0x39 { value += Double(b[i] - 0x30) * scale; scale *= 0.1; i += 1; digits += 1 }
            }
            return (digits == 0 ? nil : (negative ? -value : value), i)
        }

        mutating func target(_ px: Double?, _ py: Double?, _ pz: Double?, _ pe: Double?) -> (Double, Double, Double, Double) {
            let nx = px.map { relativeXYZ ? x + $0 : $0 } ?? x
            let ny = py.map { relativeXYZ ? y + $0 : $0 } ?? y
            let nz = pz.map { relativeXYZ ? z + $0 : $0 } ?? z
            var extruded = 0.0
            if let pe {
                if relativeE { extruded = pe } else { extruded = pe - e; e = pe }
            }
            return (nx, ny, nz, extruded)
        }

        mutating func move(_ px: Double?, _ py: Double?, _ pz: Double?, _ pe: Double?, offset: Int) {
            let (nx, ny, nz, extruded) = target(px, py, pz, pe)
            if nx != x || ny != y {
                addSegment(from: (x, y), to: (nx, ny), z: nz, extruding: extruded > 0.000_01, offset: offset)
            }
            x = nx; y = ny; z = nz
        }

        mutating func arc(clockwise: Bool, _ px: Double?, _ py: Double?, _ pz: Double?, _ pe: Double?,
                          _ pi: Double?, _ pj: Double?, offset: Int) {
            let (nx, ny, nz, extruded) = target(px, py, pz, pe)
            let cx = x + (pi ?? 0), cy = y + (pj ?? 0)
            let radius = hypot(x - cx, y - cy)
            var startAngle = atan2(y - cy, x - cx)
            var endAngle = atan2(ny - cy, nx - cx)
            if clockwise { if endAngle >= startAngle { endAngle -= 2 * .pi } } else { if endAngle <= startAngle { endAngle += 2 * .pi } }
            if radius < 0.000_1 { startAngle = endAngle }
            let sweep = endAngle - startAngle
            let steps = max(1, Int(abs(sweep) * radius / 0.5)) // ~0.5 mm chords
            var px0 = x, py0 = y
            for step in 1...steps {
                let angle = startAngle + sweep * Double(step) / Double(steps)
                let sx = step == steps ? nx : cx + radius * cos(angle)
                let sy = step == steps ? ny : cy + radius * sin(angle)
                addSegment(from: (px0, py0), to: (sx, sy), z: nz, extruding: extruded > 0.000_01, offset: offset)
                px0 = sx; py0 = sy
            }
            x = nx; y = ny; z = nz
        }

        mutating func addSegment(from a: (Double, Double), to b: (Double, Double), z segmentZ: Double, extruding: Bool, offset: Int) {
            if extruding {
                // A new layer whenever we extrude at a different height.
                if layerZ == nil || abs(segmentZ - layerZ!) > 0.005 {
                    finishLayer()
                    layerZ = segmentZ
                    layerStart = path.segments.count
                    layerOffset = offset
                }
                minX = min(minX, Float(a.0), Float(b.0)); maxX = max(maxX, Float(a.0), Float(b.0))
                minY = min(minY, Float(a.1), Float(b.1)); maxY = max(maxY, Float(a.1), Float(b.1))
            } else if layerZ == nil {
                return // travel before anything is printed
            }
            let length = hypot(b.0 - a.0, b.1 - a.1)
            path.segments.append(.init(x0: Float(a.0), y0: Float(a.1), x1: Float(b.0), y1: Float(b.1),
                                       feature: extruding ? feature : .travel, offset: Int32(clamping: offset),
                                       duration: Float(length / (feedRate / 60))))
        }

        mutating func finishLayer() {
            guard let layerZ, path.segments.count > layerStart else { return }
            path.layers.append(.init(z: Float(layerZ), segments: layerStart..<path.segments.count, fileOffset: layerOffset))
            if minX <= maxX { path.bounds = (minX, minY, maxX, maxY) }
        }
    }
}
