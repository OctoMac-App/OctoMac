import OctoPrintKit
import SwiftUI

/// Identifies a file to preview; passed to the preview window so it can be reopened and restored.
struct GCodePreviewRequest: Codable, Hashable {
    var instanceID: UUID
    var origin: String
    var path: String
}

extension GCodeToolpath.Feature {
    /// Colours follow PrusaSlicer's conventions where they exist, tuned to read on the dark graphite background.
    var color: Color {
        switch self {
        case .outerWall: Color(hex: 0xFF8A3D)
        case .innerWall: Color(hex: 0xF2C14E)
        case .overhangWall: Color(hex: 0x4F7DF0)
        case .solidInfill: Color(hex: 0xB65CE0)
        case .topSolidInfill: Color(hex: 0xF2545B)
        case .sparseInfill: Color(hex: 0xB8494A)
        case .bridgeInfill: Color(hex: 0x7FB3E0)
        case .gapFill: Color(hex: 0xEDEDED)
        case .skirt: Color(hex: 0x4FD1C5)
        case .support: Color(hex: 0x6BBF59)
        case .supportInterface: Color(hex: 0xA6E07A)
        case .wipeTower: Color(hex: 0x9AA0A8)
        case .ironing: Color(hex: 0xFFB0C8)
        case .custom: Color(hex: 0x5EC8E5)
        case .other: Color(hex: 0xC0C0C0)
        case .travel: Color(hex: 0x5EC8E5)
        }
    }
}

// MARK: - Loading

@MainActor
@Observable
final class GCodePreviewLoader {
    enum Phase {
        case downloading
        case reading(Double)
        case ready(GCodeToolpath)
        case failed(String)
    }

    private(set) var phase: Phase = .downloading

    /// Parsed files, kept while the app runs so reopening a preview is instant. Keyed by path + date.
    private static var cache: [String: GCodeToolpath] = [:]

    func load(_ file: FileEntry, client: OctoPrintClient, demo: Bool = false) async {
        let key = "\(client.baseURL.absoluteString)|\(file.id)|\(file.date?.timeIntervalSince1970 ?? 0)"
        if let cached = Self.cache[key] {
            phase = .ready(cached)
            return
        }
        phase = .downloading
        do {
            // Demo mode has no real server, so it previews a generated part instead.
            let data = demo ? Data(DemoGCode.box().utf8) : try await client.download(file)
            phase = .reading(0)
            let path = await Task.detached(priority: .userInitiated) {
                GCodeParser.parse(data) { fraction in
                    Task { @MainActor [weak self] in
                        if case .reading = self?.phase { self?.phase = .reading(fraction) }
                    }
                }
            }.value
            Self.cache[key] = path
            phase = .ready(path)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Window

struct GCodePreviewWindow: View {
    @Environment(InstanceStore.self) private var store
    let request: GCodePreviewRequest
    @State private var loader = GCodePreviewLoader()

    private var session: PrinterSession? { store.session(for: request.instanceID) }
    private var file: FileEntry? {
        session?.fileEntry(path: request.path, origin: request.origin)
    }

    var body: some View {
        ZStack {
            LayerLineBackground()
            if let session, let file {
                content(session: session, file: file)
                    .task(id: file.id) { await loader.load(file, client: session.client, demo: store.isDemo) }
            } else {
                message("This file is no longer on the printer.", symbol: "doc.questionmark")
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .preferredColorScheme(.dark)
        .navigationTitle(file.map { SlicedName($0.displayName).title } ?? "G-code preview")
    }

    @ViewBuilder
    private func content(session: PrinterSession, file: FileEntry) -> some View {
        switch loader.phase {
        case .downloading:
            progress("Downloading \(file.size.map(Fmt.bytes) ?? "file")…", value: nil)
        case .reading(let fraction):
            progress("Reading G-code…", value: fraction)
        case .failed(let reason):
            message("Couldn't load this file. \(reason)", symbol: "exclamationmark.triangle")
        case .ready(let path):
            if path.layers.isEmpty {
                message("This file doesn't contain any printing moves.", symbol: "square.stack.3d.up.slash")
            } else {
                GCodeLayerViewer(path: path, file: file, profile: session.currentProfile, filament: store.filament(for: session.instance),
                                 liveSegment: liveSegment(session: session, file: file, path: path),
                                 printSpeed: session.feedRate / 100)
            }
        }
    }

    /// The move being printed right now, when this file is the printer's current job.
    private func liveSegment(session: PrinterSession, file: FileEntry, path: GCodeToolpath) -> Int? {
        guard session.flags.isJobActive, session.job?.file.path == file.path,
              session.job?.file.origin.map({ $0 == file.origin.rawValue }) ?? true else { return nil }
        // OctoPrint reports the byte position it has sent up to; fall back to the completion percentage.
        let offset = session.progress?.filepos
            ?? session.progress?.completion.map { Int(Double(path.byteCount) * $0 / 100) }
        return offset.flatMap(path.segmentIndex(atFileOffset:))
    }

    private func progress(_ text: String, value: Double?) -> some View {
        VStack(spacing: 14) {
            BrandMark().frame(width: 64, height: 64)
            Text(text).font(Typeface.subhead).foregroundStyle(Palette.paper)
            Group {
                if let value { ProgressView(value: value) } else { ProgressView() }
            }
            .progressViewStyle(.linear)
            .tint(Palette.accent)
            .frame(width: 260)
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(Palette.faint)
            Text(text).font(Typeface.body).foregroundStyle(Palette.dust).multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Viewer

struct GCodeLayerViewer: View {
    let path: GCodeToolpath
    let file: FileEntry
    let profile: PrinterProfile?
    let filament: Color
    /// The move the printer is on, when this file is printing now.
    var liveSegment: Int? = nil
    /// The print speed factor (1 = 100%).
    var printSpeed: Double = 1
    /// Moves the 2D view's nozzle smoothly between reports (the 3D view has its own).
    @State private var playhead = LivePlayhead()

    private var liveLayer: Int? { liveSegment.flatMap(path.layerIndex(ofSegment:)) }

    enum Mode: String { case layer, threeD }

    @AppStorage("gcodePreviewMode") private var mode: Mode = .threeD
    @State private var layer = 0
    @State private var resetToken = 0
    /// The layer the live nozzle is on. While you're looking at it, the view moves on to the next layer with the
    /// nozzle; look at any other layer and it stays put until you come back.
    @State private var nozzleLayer: Int?
    @State private var hidden: Set<GCodeToolpath.Feature> = [.travel]
    @State private var showPreviousLayer = true
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private var current: GCodeToolpath.Layer { path.layers[layer] }

    /// Features present anywhere in the file, in display order.
    private var features: [GCodeToolpath.Feature] {
        let present = Set(path.segments.lazy.map(\.feature))
        return GCodeToolpath.Feature.allCases.filter(present.contains)
    }

    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 14) {
                header
                if mode == .threeD {
                    plate3D
                } else {
                    plate
                }
                layerBar
            }
            sidebar.frame(width: 250)
        }
        .padding(24)
        .padding(.top, 20)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { step(1) }
        .onKeyPress(.downArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .onKeyPress(.leftArrow) { step(-1) }
        // While printing, start on (and follow) the printer's layer. Otherwise 3D starts with the whole print and the
        // layer view at the first layer.
        .onAppear { layer = liveLayer ?? (mode == .threeD ? path.layers.count - 1 : 0) }
        .onChange(of: mode) { _, new in if new == .threeD && layer == 0 && liveLayer == nil { layer = path.layers.count - 1 } }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in followNozzle() }
        .onChange(of: liveSegment == nil) { _, ended in if ended { nozzleLayer = nil } }
        .onAppear {
            playhead.load(path)
            playhead.speed = printSpeed
            playhead.setTarget(liveSegment)
        }
        .onChange(of: liveSegment) { _, new in playhead.setTarget(new) }
        .onChange(of: printSpeed) { _, new in playhead.speed = new }
    }

    /// Watching the layer being printed right now.
    private var following: Bool { nozzleLayer != nil && layer == nozzleLayer }

    /// When the nozzle moves to a new layer, takes you with it if you were watching the one it left.
    private func followNozzle() {
        guard liveSegment != nil, let position = playhead.position() else { return }
        let current = path.layerIndex(ofSegment: min(path.segments.count - 1, Int(position)))
        guard current != nozzleLayer else { return }
        // On opening the preview you start on the printer's layer, so that counts as watching.
        if let current, layer == (nozzleLayer ?? liveLayer) { layer = current }
        nozzleLayer = current
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        layer = max(0, min(path.layers.count - 1, layer + delta))
        return .handled
    }

    // MARK: Header

    private var header: some View {
        let name = SlicedName(file.displayName)
        return HStack(alignment: .center, spacing: 12) {
            Text(name.title).font(Typeface.title).foregroundStyle(Palette.paper).lineLimit(1)
            if !name.tags.isEmpty { TagRow(tags: name.tags) }
            Spacer()
            if let nozzleLayer {
                if following {
                    LiveBadge(text: "Printing now")
                } else {
                    Button { layer = nozzleLayer } label: {
                        Label("Follow print", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(.plate)
                    .controlSize(.small)
                    .help("Jump to the layer being printed and keep up with it")
                }
            }
            HStack(spacing: 6) {
                Chip(title: "Layer", selected: mode == .layer) { mode = .layer }
                Chip(title: "3D", selected: mode == .threeD) { mode = .threeD }
            }
            .padding(.trailing, 8)
            Text("Layer \(layer + 1) of \(path.layers.count)").font(Typeface.number(17)).foregroundStyle(Palette.paper)
            Text(String(format: "Z %.2f mm", current.z)).font(Typeface.number(17)).foregroundStyle(filament)
        }
    }

    // MARK: Plate

    /// The area to frame: the printer's bed when known, otherwise the print's extent.
    private var bed: CGRect {
        if let width = profile?.volume?.width, let depth = profile?.volume?.depth, width > 0, depth > 0 {
            return CGRect(x: 0, y: 0, width: width, height: depth)
        }
        let b = path.bounds ?? (0, 0, 200, 200)
        return CGRect(x: CGFloat(b.minX) - 10, y: CGFloat(b.minY) - 10,
                      width: CGFloat(b.maxX - b.minX) + 20, height: CGFloat(b.maxY - b.minY) + 20)
    }

    private var plate: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / bed.width, geo.size.height / bed.height) * 0.94 * zoom * pinch
            let offset = CGSize(width: pan.width + drag.width, height: pan.height + drag.height)
            // While printing, redraw every frame so the nozzle glides along the moves.
            TimelineView(.animation(minimumInterval: 1 / 30, paused: liveSegment == nil)) { _ in
            let livePosition = liveSegment == nil ? nil : playhead.position()
            Canvas { context, size in
                // Printer coordinates (mm, Y up) → view coordinates.
                let origin = CGPoint(x: size.width / 2 - bed.midX * scale + offset.width,
                                     y: size.height / 2 + bed.midY * scale + offset.height)
                func point(_ x: Float, _ y: Float) -> CGPoint {
                    CGPoint(x: origin.x + CGFloat(x) * scale, y: origin.y - CGFloat(y) * scale)
                }

                drawBed(&context, origin: origin, scale: scale)

                let lineWidth = max(1, 0.45 * scale)
                if showPreviousLayer, layer > 0 {
                    var previous = Path()
                    for s in path.segments(in: path.layers[layer - 1]) where s.feature != .travel {
                        previous.move(to: point(s.x0, s.y0))
                        previous.addLine(to: point(s.x1, s.y1))
                    }
                    context.stroke(previous, with: .color(.white.opacity(0.10)),
                                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }

                // One path per feature, so each layer is a handful of draw calls rather than thousands.
                var byFeature: [GCodeToolpath.Feature: Path] = [:]
                // While printing, the layer being printed is drawn only up to the nozzle.
                let liveIndex = livePosition.map { min(path.segments.count - 1, Int($0)) }
                let liveFraction = livePosition.map { Float(min(1, $0 - Double(Int($0)))) } ?? 1
                let liveCut = liveIndex.flatMap { path.layerIndex(ofSegment: $0) == layer ? $0 : nil }
                let range = current.segments
                let upTo = liveCut.map { min(range.upperBound, max(range.lowerBound, $0)) } ?? range.upperBound
                for s in path.segments[range.lowerBound..<max(range.lowerBound, upTo)] where !hidden.contains(s.feature) {
                    byFeature[s.feature, default: Path()].move(to: point(s.x0, s.y0))
                    byFeature[s.feature, default: Path()].addLine(to: point(s.x1, s.y1))
                }
                // The move the nozzle is on, drawn as far as it has got.
                if let liveCut, liveCut < path.segments.count, !hidden.contains(path.segments[liveCut].feature) {
                    let s = path.segments[liveCut]
                    byFeature[s.feature, default: Path()].move(to: point(s.x0, s.y0))
                    byFeature[s.feature, default: Path()].addLine(to: point(s.x0 + (s.x1 - s.x0) * liveFraction, s.y0 + (s.y1 - s.y0) * liveFraction))
                }
                defer {
                    if let liveCut, liveCut < path.segments.count {
                        let s = path.segments[liveCut]
                        let tip = point(s.x0 + (s.x1 - s.x0) * liveFraction, s.y0 + (s.y1 - s.y0) * liveFraction)
                        let glow = max(12, lineWidth * 4)
                        context.fill(Path(ellipseIn: CGRect(x: tip.x - glow, y: tip.y - glow, width: glow * 2, height: glow * 2)),
                                     with: .radialGradient(Gradient(colors: [Color(hex: 0xFF9430).opacity(0.75), .clear]),
                                                           center: tip, startRadius: 0, endRadius: glow))
                        let dot = max(4.5, lineWidth * 1.2)
                        context.fill(Path(ellipseIn: CGRect(x: tip.x - dot, y: tip.y - dot, width: dot * 2, height: dot * 2)),
                                     with: .color(Color(hex: 0xFFD27A)))
                    }
                }
                for (feature, featurePath) in byFeature {
                    if feature == .travel {
                        context.stroke(featurePath, with: .color(feature.color.opacity(0.55)),
                                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    } else {
                        context.stroke(featurePath, with: .color(feature.color),
                                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            }
            .contentShape(Rectangle())
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = max(0.5, min(40, zoom * value.magnification)) }
                    .simultaneously(with:
                        DragGesture()
                            .updating($drag) { value, state, _ in state = value.translation }
                            .onEnded { value in pan.width += value.translation.width; pan.height += value.translation.height }
                    )
            )
            .onTapGesture(count: 2) { withAnimation(.snappy) { zoom = 1; pan = .zero } }
            .overlay(alignment: .bottomTrailing) { zoomControls }
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.rail))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.05), lineWidth: 1))
    }

    private var plate3D: some View {
        GCode3DView(path: path, bed: bed, maxLayer: following ? path.layers.count - 1 : layer, liveSegment: liveSegment,
                    printSpeed: printSpeed, hidden: hidden,
                    nozzleWidth: Float(profile?.extruder?.nozzleDiameter ?? 0.4) * 1.12, resetToken: resetToken)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.05), lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                Button { resetToken += 1 } label: {
                    Label("Reset view", systemImage: "arrow.counterclockwise")
                        .font(Typeface.text(12, .demibold))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.paper)
                .background(Capsule().fill(Palette.extrusion.opacity(0.92)))
                .overlay(Capsule().strokeBorder(Palette.edge, lineWidth: 1))
                .padding(14)
                .help("Reset the camera (or double-click the model)")
            }
    }

    private func drawBed(_ context: inout GraphicsContext, origin: CGPoint, scale: CGFloat) {
        let rect = CGRect(x: origin.x + bed.minX * scale, y: origin.y - bed.maxY * scale,
                          width: bed.width * scale, height: bed.height * scale)
        context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(Palette.graphite))
        // 10 mm grid, every 50 mm a little stronger
        var minor = Path(), major = Path()
        var x = (bed.minX / 10).rounded(.up) * 10
        while x <= bed.maxX {
            let vx = origin.x + x * scale
            var line = Path(); line.move(to: CGPoint(x: vx, y: rect.minY)); line.addLine(to: CGPoint(x: vx, y: rect.maxY))
            if Int(x) % 50 == 0 { major.addPath(line) } else { minor.addPath(line) }
            x += 10
        }
        var y = (bed.minY / 10).rounded(.up) * 10
        while y <= bed.maxY {
            let vy = origin.y - y * scale
            var line = Path(); line.move(to: CGPoint(x: rect.minX, y: vy)); line.addLine(to: CGPoint(x: rect.maxX, y: vy))
            if Int(y) % 50 == 0 { major.addPath(line) } else { minor.addPath(line) }
            y += 10
        }
        context.stroke(minor, with: .color(.white.opacity(0.035)), lineWidth: 1)
        context.stroke(major, with: .color(.white.opacity(0.08)), lineWidth: 1)
        context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(.white.opacity(0.12)), lineWidth: 1)
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            zoomButton("minus") { zoom = max(0.5, zoom / 1.5) }
            Button { withAnimation(.snappy) { zoom = 1; pan = .zero } } label: {
                Text("\(Int((zoom * 100).rounded()))%").font(Typeface.number(12))
                    .frame(minWidth: 48, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.dust)
            .help("Fit to bed (or double-click the plate)")
            zoomButton("plus") { zoom = min(40, zoom * 1.5) }
        }
        .padding(4)
        .background(Capsule().fill(Palette.extrusion.opacity(0.92)))
        .overlay(Capsule().strokeBorder(Palette.edge, lineWidth: 1))
        .padding(14)
    }

    private func zoomButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                .frame(width: 36, height: 32)
                .contentShape(Rectangle()) // the whole button is clickable, not just the glyph
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.paper)
    }

    // MARK: Layer bar

    private var layerBar: some View {
        HStack(spacing: 12) {
            stepButton("chevron.left", help: "Previous layer (←)") { _ = step(-1) }
            // Continuous slider (rounded to whole layers); a stepped one draws a tick per layer.
            Slider(value: Binding(get: { Double(layer) }, set: { layer = Int($0.rounded()) }),
                   in: 0...Double(max(1, path.layers.count - 1)))
                .tint(Palette.accent)
            stepButton("chevron.right", help: "Next layer (→)") { _ = step(1) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .machined(radius: 16)
    }

    private func stepButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.paper)
        .help(help)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        let layerSegments = path.segments(in: current)
        let counts = Dictionary(grouping: layerSegments, by: \.feature).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Show").font(Typeface.bodyStrong).foregroundStyle(Palette.dust)
                ForEach(features, id: \.self) { feature in
                    Button { toggle(feature) } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(hidden.contains(feature) ? Color.clear : feature.color)
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(feature.color, lineWidth: 1.5))
                                .frame(width: 14, height: 14)
                            Text(feature.displayName).font(Typeface.body)
                                .foregroundStyle(hidden.contains(feature) ? Palette.faint : Palette.paper)
                            Spacer()
                            if let count = counts[feature] {
                                Text("\(count)").font(Typeface.number(12)).foregroundStyle(Palette.faint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if mode == .layer {
                    Divider().overlay(Palette.edge)
                    Toggle("Show the layer below", isOn: $showPreviousLayer)
                        .toggleStyle(.switch)
                        .tint(Palette.accent)
                        .font(Typeface.body)
                        .foregroundStyle(Palette.dust)
                }
            }
            .padding(16)
            .machined(radius: 16)

            VStack(alignment: .leading, spacing: 8) {
                fact("Layers", "\(path.layers.count)")
                fact("Height", String(format: "%.2f mm", path.layers.last?.z ?? 0))
                if let time = file.expectedPrintTime?.seconds { fact("Print time", Fmt.duration(time)) }
                if let length = file.gcodeAnalysis?.totalFilamentLength { fact("Filament", Fmt.filament(length)) }
                fact("Moves in this layer", "\(layerSegments.count.formatted())")
            }
            .padding(16)
            .machined(radius: 16)

            Spacer()

            Text(mode == .threeD
                 ? "Drag to rotate, scroll or pinch to zoom, right-drag or ⌥-drag to move. Double-click to reset. The slider cuts the print off at any layer."
                 : "Pinch or use the buttons to zoom, drag to move, double-click to fit. Arrow keys step through layers.")
                .font(Typeface.caption)
                .foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggle(_ feature: GCodeToolpath.Feature) {
        if hidden.contains(feature) { hidden.remove(feature) } else { hidden.insert(feature) }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(Typeface.caption).foregroundStyle(Palette.faint)
            Spacer()
            Text(value).font(Typeface.number(14)).foregroundStyle(Palette.paper)
        }
    }
}

/// A small "live" pill with a pulsing dot.
struct LiveBadge: View {
    let text: String
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Palette.accent).frame(width: 8, height: 8)
                .scaleEffect(pulse ? 1.25 : 0.8)
                .opacity(pulse ? 1 : 0.55)
            Text(text).font(Typeface.text(12, .demibold)).foregroundStyle(Palette.paper)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.accent.opacity(0.16)))
        .overlay(Capsule().strokeBorder(Palette.accent.opacity(0.5), lineWidth: 1))
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

/// Generated G-code for demo mode: a 60 × 40 × 24 mm tray with walls, a solid floor and alternating infill.
enum DemoGCode {
    static func box() -> String {
        var lines = ["; generated by OctoMac for demo mode", "M83", "G28"]
        let x0 = 70.0, y0 = 80.0, width = 60.0, depth = 40.0, layerHeight = 0.2, layers = 120
        func loop(_ inset: Double) {
            let a = (x0 + inset, y0 + inset), b = (x0 + width - inset, y0 + depth - inset)
            lines.append("G1 X\(a.0) Y\(a.1)")
            for p in [(b.0, a.1), (b.0, b.1), (a.0, b.1), (a.0, a.1)] {
                lines.append("G1 X\(p.0) Y\(p.1) E0.5")
            }
        }
        for n in 0..<layers {
            let z = Double(n + 1) * layerHeight
            lines.append(";LAYER_CHANGE")
            lines.append(String(format: "G1 Z%.2f", z))
            lines.append(";TYPE:External perimeter")
            loop(0)
            lines.append(";TYPE:Perimeter")
            loop(0.45)
            let solid = n < 4
            lines.append(solid ? ";TYPE:Solid infill" : ";TYPE:Internal infill")
            let spacing = solid ? 0.45 : 4.0
            var i = 0
            var x = x0 + 1.2
            while x < x0 + width - 1.2 {
                let (from, to) = i % 2 == 0 ? (y0 + 1.2, y0 + depth - 1.2) : (y0 + depth - 1.2, y0 + 1.2)
                if n % 2 == 0 {
                    lines.append(String(format: "G1 X%.2f Y%.2f", x, from))
                    lines.append(String(format: "G1 X%.2f Y%.2f E0.3", x, to))
                } else {
                    let yy = y0 + 1.2 + (x - x0 - 1.2) * (depth - 2.4) / (width - 2.4)
                    let (l, r) = i % 2 == 0 ? (x0 + 1.2, x0 + width - 1.2) : (x0 + width - 1.2, x0 + 1.2)
                    lines.append(String(format: "G1 X%.2f Y%.2f", l, yy))
                    lines.append(String(format: "G1 X%.2f Y%.2f E0.3", r, yy))
                }
                x += spacing
                i += 1
            }
        }
        return lines.joined(separator: "\n")
    }
}
