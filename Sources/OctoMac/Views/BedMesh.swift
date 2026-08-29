import OctoPrintKit
import SwiftUI

/// The Bed Level Visualizer panel on the Machine tab: the latest bed mesh as a map or a 3D surface,
/// with a button to measure the bed again.
struct BedMeshPanel: View {
    let session: PrinterSession
    let settings: BedLevelVisualizer.Settings
    @State private var style = Style.map
    @State private var editingCommand = false

    enum Style: String, CaseIterable { case map = "Map", surface = "3D" }

    var body: some View {
        StagePanel(title: "Bed level", detail: session.bedMesh?.measured.map { "Measured \($0)" }) {
            VStack(alignment: .leading, spacing: 18) {
                if let mesh = session.bedMesh {
                    HStack(alignment: .top, spacing: 24) {
                        Group {
                            switch style {
                            case .map: BedMeshMap(mesh: mesh)
                            case .surface: BedMeshSurface(mesh: mesh)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .overlay {
                            if session.bedMeasuringSince != nil {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.graphite.opacity(0.7))
                                ProgressView().controlSize(.large).tint(Palette.accent)
                            }
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            stat("Spread", mesh.spread, help: "Highest point minus lowest point. Under 0.2 mm is good for most printers.")
                            stat("Highest", mesh.maximum, signed: true)
                            stat("Lowest", mesh.minimum, signed: true)
                            BedMeshLegend(limit: BedMeshColors.limit(for: mesh))
                        }
                        .frame(width: 150, alignment: .leading)
                    }
                } else {
                    Text(session.bedMeasuringSince == nil
                         ? "No bed mesh yet. Measure the bed to see how flat it is."
                         : "Measuring the bed. This takes a minute or two.")
                        .font(Typeface.body).foregroundStyle(Palette.dust)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                }

                controls
            }
        }
        .sheet(isPresented: $editingCommand) {
            BedCommandSheet(session: session, command: settings.command)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if session.bedMesh != nil {
                Picker("View", selection: $style) {
                    ForEach(Style.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Spacer()
            if !settings.canMeasure {
                Text("Bed Visualizer needs the G-code that measures your bed.")
                    .font(Typeface.caption).foregroundStyle(Palette.warm)
                Button { editingCommand = true } label: { Label("Set up measuring", systemImage: "slider.horizontal.3") }
                    .buttonStyle(.plate)
            } else if session.bedMeasuringSince != nil {
                Button { session.cancelBedMeasurement() } label: { Label("Stop measuring", systemImage: "xmark") }
                    .buttonStyle(.plateQuiet)
            } else {
                Button("G-code…") { editingCommand = true }
                    .buttonStyle(.plateQuiet)
                    .help("The commands Bed Visualizer sends to measure the bed")
                Button { session.measureBed() } label: { Label("Measure bed", systemImage: "square.grid.3x3.middle.filled") }
                    .buttonStyle(.plate)
                    .disabled(!session.canControl)
                    .help(session.controlBlocker ?? "Homes the printer and probes the bed")
            }
        }
    }

    private func stat(_ title: String, _ value: Double?, signed: Bool = false, help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Typeface.caption).foregroundStyle(Palette.faint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map { BedMeshColors.format($0, signed: signed) } ?? "–")
                    .font(Typeface.number(24)).foregroundStyle(Palette.paper)
                Text("mm").font(Typeface.number(13)).foregroundStyle(Palette.faint)
            }
        }
        .help(help ?? "")
    }
}

/// Colours for bed heights: blue below the reference, green near it, orange and red above.
enum BedMeshColors {
    /// The height that gets the strongest colour. At least 0.1 mm, so a very flat bed doesn't look dramatic.
    static func limit(for mesh: BedLevelVisualizer.Mesh) -> Double {
        max(0.1, mesh.values.map(abs).max() ?? 0.1)
    }

    static func color(_ value: Double, limit: Double) -> Color {
        let t = max(-1, min(1, value / limit))
        if t < 0 { return mix(Palette.accent, Palette.cold, -t) }
        return t < 0.5 ? mix(Palette.accent, Palette.warm, t * 2) : mix(Palette.warm, Palette.hot, (t - 0.5) * 2)
    }

    static func format(_ value: Double, signed: Bool) -> String {
        let text = String(format: "%.3f", value)
        return signed && value > 0 ? "+" + text : text
    }

    private static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ra = NSColor(a).usingColorSpace(.sRGB) ?? .gray, rb = NSColor(b).usingColorSpace(.sRGB) ?? .gray
        return Color(red: ra.redComponent + (rb.redComponent - ra.redComponent) * t,
                     green: ra.greenComponent + (rb.greenComponent - ra.greenComponent) * t,
                     blue: ra.blueComponent + (rb.blueComponent - ra.blueComponent) * t)
    }
}

struct BedMeshLegend: View {
    let limit: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LinearGradient(stops: [-1, -0.5, 0, 0.5, 1].map { .init(color: BedMeshColors.color($0 * limit, limit: limit), location: ($0 + 1) / 2) },
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 8)
                .clipShape(Capsule())
            HStack {
                Text(BedMeshColors.format(-limit, signed: true))
                Spacer()
                Text(BedMeshColors.format(limit, signed: true))
            }
            .font(Typeface.number(11)).foregroundStyle(Palette.faint)
        }
    }
}

/// The bed seen from above, back of the bed at the top, each probe point with its height.
struct BedMeshMap: View {
    let mesh: BedLevelVisualizer.Mesh

    var body: some View {
        let limit = BedMeshColors.limit(for: mesh)
        let rows = mesh.z.count
        let columns = mesh.z.first?.count ?? 0
        VStack(spacing: 4) {
            Text("Back").font(Typeface.caption).foregroundStyle(Palette.faint)
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                // Row 0 is the front of the bed, so draw from the last row down.
                ForEach((0..<rows).reversed(), id: \.self) { row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            cell(mesh.z[row].indices.contains(column) ? mesh.z[row][column] : nil, limit: limit, dense: columns > 7)
                                .help(position(row: row, column: column))
                        }
                    }
                }
            }
            Text("Front").font(Typeface.caption).foregroundStyle(Palette.faint)
        }
    }

    private func cell(_ value: Double?, limit: Double, dense: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(value.map { BedMeshColors.color($0, limit: limit) } ?? Palette.graphite)
            if let value {
                Text(BedMeshColors.format(value, signed: true).replacingOccurrences(of: "0.", with: dense ? "." : "0."))
                    .font(Typeface.number(dense ? 10 : 12))
                    .foregroundStyle(Palette.graphite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func position(row: Int, column: Int) -> String {
        let x = mesh.x.indices.contains(column) ? "X \(Int(mesh.x[column]))" : "Column \(column + 1)"
        let y = mesh.y.indices.contains(row) ? "Y \(Int(mesh.y[row]))" : "Row \(row + 1)"
        return "\(x), \(y) mm"
    }
}

/// The bed as a 3D surface with the heights exaggerated, so bumps and tilt are easy to see. Drag to turn it.
struct BedMeshSurface: View {
    let mesh: BedLevelVisualizer.Mesh
    @State private var yaw = -0.6
    @State private var dragStart: Double?

    var body: some View {
        let limit = BedMeshColors.limit(for: mesh)
        Canvas { context, size in
            let rows = mesh.z.count, columns = mesh.z.first?.count ?? 0
            guard rows > 1, columns > 1 else { return }
            // A turned square spans up to √2 of its side, so leave room for that at any angle.
            let scale = min(size.width / 3, size.height / 2.2)
            let pitch = 0.95
            // Heights scaled so the largest bump stands about a fifth of the bed's width.
            let zScale = 0.4 / limit

            func project(_ column: Int, _ row: Int, _ z: Double) -> (CGPoint, Double) {
                let x = Double(column) / Double(columns - 1) * 2 - 1
                let y = Double(row) / Double(rows - 1) * 2 - 1
                let rx = x * cos(yaw) - y * sin(yaw)
                let ry = x * sin(yaw) + y * cos(yaw)
                let depth = ry * cos(pitch) - z * zScale * sin(pitch)
                let screenY = ry * sin(pitch) + z * zScale * cos(pitch)
                return (CGPoint(x: size.width / 2 + rx * scale, y: size.height / 2 - screenY * scale * 0.9 + scale * 0.1), depth)
            }

            struct Face { var path: Path; var depth: Double; var height: Double }
            var faces: [Face] = []
            for row in 0..<(rows - 1) {
                for column in 0..<(columns - 1) {
                    let corners = [(column, row), (column + 1, row), (column + 1, row + 1), (column, row + 1)]
                    let heights = corners.map { mesh.z[$0.1].indices.contains($0.0) ? mesh.z[$0.1][$0.0] : nil }
                    guard heights.allSatisfy({ $0 != nil }) else { continue }
                    let points = zip(corners, heights).map { project($0.0, $0.1, $1!) }
                    var path = Path()
                    path.addLines(points.map(\.0))
                    path.closeSubpath()
                    let average = heights.compactMap { $0 }.reduce(0, +) / 4
                    faces.append(Face(path: path, depth: points.map(\.1).reduce(0, +) / 4, height: average))
                }
            }
            // Painter's algorithm: far faces first.
            for face in faces.sorted(by: { $0.depth > $1.depth }) {
                context.fill(face.path, with: .color(BedMeshColors.color(face.height, limit: limit)))
                context.stroke(face.path, with: .color(Palette.graphite.opacity(0.55)), lineWidth: 1)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.graphite))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil { dragStart = yaw }
                yaw = (dragStart ?? yaw) + value.translation.width / 160
            }
            .onEnded { _ in dragStart = nil })
        .overlay(alignment: .bottomTrailing) {
            Text("Drag to turn. Heights exaggerated.")
                .font(Typeface.caption).foregroundStyle(Palette.faint)
                .padding(10)
        }
    }
}

/// Edits the G-code Bed Visualizer sends to measure the bed (saved in the plugin's settings).
struct BedCommandSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    @State var command: String

    private let suggestions: [(name: String, gcode: String)] = [
        ("Prusa MK3S, MK2.5S", "@BEDLEVELVISUALIZER\nG28 W\nG80\nG81"),
        ("Marlin, probe", "@BEDLEVELVISUALIZER\nG28\nG29 T"),
        ("Marlin, saved mesh", "@BEDLEVELVISUALIZER\nM420 V"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to measure the bed").font(Typeface.title).foregroundStyle(Palette.paper)
            Text("Bed Visualizer sends these commands, one per line, and reads the printer's reply. Start with @BEDLEVELVISUALIZER, which tells the plugin to listen. They're saved in OctoPrint, so its own Bed Visualizer page uses them too.")
                .font(Typeface.body).foregroundStyle(Palette.dust)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $command)
                .font(Typeface.number(14))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 130)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.graphite))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.edge, lineWidth: 1))
            Link(destination: BedLevelVisualizer.guideURL) {
                Label("Bed Visualizer's guide has G-code for other printers", systemImage: "arrow.up.right.square")
                    .font(Typeface.caption)
            }
            .foregroundStyle(Palette.accent)
            HStack(spacing: 8) {
                Text("Start from:").font(Typeface.caption).foregroundStyle(Palette.faint)
                ForEach(suggestions, id: \.name) { suggestion in
                    Button(suggestion.name) { command = suggestion.gcode }
                        .buttonStyle(.plateQuiet)
                        .controlSize(.small)
                        .fixedSize()
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plateQuiet).keyboardShortcut(.cancelAction)
                Button("Save") {
                    session.setBedMeasureCommand(command.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .buttonStyle(.plate)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 560)
        .background(Palette.extrusion)
    }
}
