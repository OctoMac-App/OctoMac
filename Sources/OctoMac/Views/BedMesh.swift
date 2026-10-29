import OctoPrintKit
import SwiftUI

/// The Bed Level Visualizer panel on the Machine tab: the latest bed mesh as a map or a 3D surface,
/// with a button to measure the bed again.
struct BedMeshPanel: View {
    let session: PrinterSession
    let settings: BedLevelVisualizer.Settings
    @State private var style = Style.map
    @State private var editingCommand = false
    /// An earlier measurement to look at, or nil for the latest.
    @State private var earlier: Date?
    @State private var showsChange = true

    enum Style: String, CaseIterable { case map = "Map", surface = "3D" }

    /// Earlier measurements, newest first (the latest is the panel's usual view).
    private var history: [PrinterJournal.Mesh] { Array(session.journal.meshes.dropLast().reversed()) }

    /// What the map shows: the latest bed, an earlier one, or how much each point has moved since then.
    private var shown: (mesh: BedLevelVisualizer.Mesh, detail: LocalizedStringKey?, isChange: Bool)? {
        guard let latest = session.bedMesh else { return nil }
        guard let earlier, let past = session.journal.meshes.first(where: { $0.date == earlier }) else {
            return (latest, latest.measured.map { measured -> LocalizedStringKey in "Measured \(measured)" }, false)
        }
        let then = past.mesh
        let when = past.date.formatted(date: .abbreviated, time: .shortened)
        if showsChange, let change = latest.change(since: then) {
            return (change, "Change since \(when)", true)
        }
        return (then, "Measured \(when)", false)
    }

    var body: some View {
        let shown = shown
        StagePanel(title: "Bed level", detail: shown?.detail) {
            VStack(alignment: .leading, spacing: 18) {
                if !history.isEmpty, session.bedMesh != nil {
                    HStack(spacing: 12) {
                        PlateMenu(selection: $earlier, options: [(nil, String(localized: "Latest measurement"))]
                                  + history.map { ($0.date, $0.date.formatted(date: .abbreviated, time: .shortened)) })
                            .frame(maxWidth: 240)
                        if earlier != nil {
                            CapsulePicker(selection: $showsChange, options: [(true, "Change since"), (false, "As it was")], compact: true)
                        }
                        Spacer()
                    }
                }
                if let shown {
                    let mesh = shown.mesh
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
                            if shown.isChange {
                                stat("Rose by up to", mesh.maximum, signed: true,
                                     help: "How far each point has moved since the earlier measurement. Above zero is higher now.")
                                stat("Dropped by up to", mesh.minimum, signed: true)
                                stat("Spread now", session.bedMesh?.spread, help: "Highest point minus lowest point on the latest measurement.")
                            } else {
                                stat("Spread", mesh.spread, help: "Highest point minus lowest point. Under 0.2 mm is good for most printers.")
                                stat("Highest", mesh.maximum, signed: true)
                                stat("Lowest", mesh.minimum, signed: true)
                            }
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
                CapsulePicker(selection: $style, options: [(.map, "Map"), (.surface, "3D")], compact: true)
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
                    .help(session.controlBlocker ?? String(localized: "Homes the printer and probes the bed"))
            }
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: Double?, signed: Bool = false, help: LocalizedStringKey? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Typeface.caption).foregroundStyle(Palette.faint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map { BedMeshColors.format($0, signed: signed) } ?? "–")
                    .font(Typeface.number(24)).foregroundStyle(Palette.paper)
                Text(verbatim: "mm").font(Typeface.number(13)).foregroundStyle(Palette.faint)
            }
        }
        .help(help.map { Text($0) } ?? Text(verbatim: ""))
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
        let text = Fmt.decimal(value, 3)
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
        let x = mesh.x.indices.contains(column) ? "X \(Int(mesh.x[column]))" : String(localized: "Column \(column + 1)")
        let y = mesh.y.indices.contains(row) ? "Y \(Int(mesh.y[row]))" : String(localized: "Row \(row + 1)")
        return "\(x), \(y) mm"
    }
}

/// The bed as a 3D surface with the heights exaggerated, so bumps and tilt are easy to see.
/// Drag sideways to spin it and up or down to tip it, all the way round; the underside is solid so it's clear
/// when you're looking from below. Double-click to go back to the starting view.
struct BedMeshSurface: View {
    let mesh: BedLevelVisualizer.Mesh
    private static let startYaw = -0.6, startPitch = 0.95
    /// One flat colour for the bottom of the bed, so it never looks like part of the height map.
    private static let underside = Color(hex: 0x58606C)
    @State private var yaw = startYaw
    @State private var pitch = startPitch
    @State private var dragStart: (yaw: Double, pitch: Double)?

    var body: some View {
        let limit = BedMeshColors.limit(for: mesh)
        Canvas { context, size in
            let rows = mesh.z.count, columns = mesh.z.first?.count ?? 0
            guard rows > 1, columns > 1 else { return }
            // A turned square spans up to √2 of its side in any direction, so leave room for that.
            let scale = min(size.width, size.height) / 3.1
            // Heights scaled so the largest bump stands about a fifth of the bed's width.
            let zScale = 0.4 / limit

            /// Bed coordinates (x and y from -1 to 1, front edge at y = -1) to the screen, plus depth (larger is further away).
            func project(x: Double, y: Double, height: Double) -> (point: CGPoint, depth: Double) {
                let rx = x * cos(yaw) - y * sin(yaw)
                let ry = x * sin(yaw) + y * cos(yaw)
                let depth = ry * cos(pitch) - height * sin(pitch)
                let up = ry * sin(pitch) + height * cos(pitch)
                return (CGPoint(x: size.width / 2 + rx * scale, y: size.height / 2 - up * scale), depth)
            }
            func project(_ column: Int, _ row: Int, _ z: Double) -> (point: CGPoint, depth: Double) {
                project(x: Double(column) / Double(columns - 1) * 2 - 1,
                        y: Double(row) / Double(rows - 1) * 2 - 1,
                        height: z * zScale)
            }

            struct Face { var path: Path; var depth: Double; var height: Double; var underside: Bool }
            var faces: [Face] = []
            for row in 0..<(rows - 1) {
                for column in 0..<(columns - 1) {
                    let corners = [(column, row), (column + 1, row), (column + 1, row + 1), (column, row + 1)]
                    let heights = corners.map { mesh.z[$0.1].indices.contains($0.0) ? mesh.z[$0.1][$0.0] : nil }
                    guard heights.allSatisfy({ $0 != nil }) else { continue }
                    let projected = zip(corners, heights).map { project($0.0, $0.1, $1!) }
                    let points = projected.map(\.point)
                    var path = Path()
                    path.addLines(points)
                    path.closeSubpath()
                    // Seen from above, the corners run one way round on screen; from below, the other way.
                    var area = 0.0
                    for index in points.indices {
                        let a = points[index], b = points[(index + 1) % points.count]
                        area += Double(a.x * b.y) - Double(b.x * a.y)
                    }
                    faces.append(Face(path: path, depth: projected.map(\.depth).reduce(0, +) / 4,
                                      height: heights.compactMap { $0 }.reduce(0, +) / 4, underside: area > 0))
                }
            }
            // Painter's algorithm: far faces first.
            for face in faces.sorted(by: { $0.depth > $1.depth }) {
                context.fill(face.path, with: .color(face.underside ? Self.underside : BedMeshColors.color(face.height, limit: limit)))
                context.stroke(face.path, with: .color(Palette.graphite.opacity(face.underside ? 0.8 : 0.55)), lineWidth: 1)
            }

            // Which way round the bed is: labels just beyond the front and back edges, dimmer when on the far side.
            for (label, y) in [(String(localized: "Front", comment: "The front edge of the print bed"), -1.25),
                               (String(localized: "Back", comment: "The back edge of the print bed"), 1.25)] {
                let spot = project(x: 0, y: y, height: 0)
                let text = Text(verbatim: label).font(Typeface.text(12, .demibold))
                    .foregroundStyle(spot.depth > 0 ? Palette.faint : Palette.paper)
                context.draw(text, at: spot.point)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.graphite))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil { dragStart = (yaw, pitch) }
                yaw = (dragStart?.yaw ?? yaw) + value.translation.width / 160
                pitch = (dragStart?.pitch ?? pitch) + value.translation.height / 160
            }
            .onEnded { _ in dragStart = nil })
        .onTapGesture(count: 2) {
            withAnimation(.snappy) {
                yaw = Self.startYaw
                pitch = Self.startPitch
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text("Drag to turn any way. Double-click to reset. Heights exaggerated.")
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
        (String(localized: "Marlin, probe"), "@BEDLEVELVISUALIZER\nG28\nG29 T"),
        (String(localized: "Marlin, saved mesh"), "@BEDLEVELVISUALIZER\nM420 V"),
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
            HStack(spacing: 18) {
                Link(destination: BedLevelVisualizer.gcodeExamplesURL) {
                    Label("G-code examples for other printers", systemImage: "arrow.up.right.square")
                }
                Link(destination: BedLevelVisualizer.guideURL) {
                    Label("Bed Visualizer guide", systemImage: "arrow.up.right.square")
                }
            }
            .font(Typeface.caption)
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
