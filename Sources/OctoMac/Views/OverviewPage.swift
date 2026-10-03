import Charts
import OctoPrintKit
import SwiftUI

struct OverviewPage: View {
    let session: PrinterSession
    let filament: Color
    @Binding var tab: StageTab
    @State private var cinema = false

    var body: some View {
        GeometryReader { geo in
            // Laptops and small windows: a stacked layout that scrolls, instead of squeezing everything in.
            if geo.size.width < 860 || geo.size.height < 600 {
                stacked(width: geo.size.width)
                    .overlay {
                        if cinema {
                            CinemaCamera(session: session, filament: filament, cinema: $cinema)
                                .transition(.opacity)
                        }
                    }
            } else {
                spread(size: geo.size)
            }
        }
    }

    /// Everything on one screen: camera and job side by side, temperatures below.
    private func spread(size: CGSize) -> some View {
        let topHeight = size.height * 0.5
        // Camera keeps a 16:9 frame and gives the rest of the row to the job / files panel.
        let cameraWidth = min(topHeight * 16 / 9, size.width * 0.58)
        return VStack(spacing: 20) {
            banner
            HStack(spacing: 20) {
                Color.clear
                    .frame(width: cameraWidth)
                    .anchorPreference(key: CameraSlotKey.self, value: .bounds) { $0 }
                jobOrFiles
            }
            .frame(height: topHeight)

            HStack(alignment: .top, spacing: 20) {
                // Full-size tiles need about 440 points under the presets; shorter windows get the compact rows.
                heaterColumn(fill: true, compact: size.height - topHeight - 20 < 440).frame(width: 300)
                TemperaturePanel(session: session)
            }
            .frame(maxHeight: .infinity)
        }
        .opacity(cinema ? 0 : 1)
        // One camera view moves between its slot and the whole stage.
        .overlayPreferenceValue(CameraSlotKey.self) { anchor in
            GeometryReader { proxy in
                let rect = cinema || anchor == nil ? CGRect(origin: .zero, size: proxy.size) : proxy[anchor!]
                CinemaCamera(session: session, filament: filament, cinema: $cinema)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
    }

    /// Small windows: sections stack and the page scrolls.
    private func stacked(width: CGFloat) -> some View {
        let narrow = width < 860
        return ScrollView {
            VStack(spacing: 16) {
                banner
                if narrow {
                    CinemaCamera(session: session, filament: filament, cinema: $cinema)
                        .aspectRatio(16 / 9, contentMode: .fit)
                    jobOrFiles.frame(height: 380)
                } else {
                    HStack(spacing: 16) {
                        CinemaCamera(session: session, filament: filament, cinema: $cinema)
                            .aspectRatio(16 / 9, contentMode: .fit)
                        jobOrFiles
                    }
                    .frame(height: 340)
                }
                if narrow {
                    heaterColumn(fill: false)
                    TemperaturePanel(session: session).frame(height: 300)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        heaterColumn(fill: false).frame(width: 280)
                        TemperaturePanel(session: session).frame(height: 340)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.automatic)
        .opacity(cinema ? 0 : 1)
    }

    @ViewBuilder private var banner: some View {
        if session.link == .online && !session.isPrinterConnected {
            PrinterOfflineBanner(session: session, tab: $tab)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var jobOrFiles: some View {
        Group {
            if session.flags.isJobActive {
                JobPanel(session: session, filament: filament, tab: $tab)
            } else {
                ReadyPanel(session: session, filament: filament, tab: $tab)
            }
        }
        // Never let the panel's content widen the row past the window.
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Presets and heaters. `fill` stretches big tiles to the available height (the one-screen layout).
    private func heaterColumn(fill: Bool, compact: Bool = false) -> some View {
        VStack(spacing: 14) {
            PresetPanel(session: session)
            if sortedHeaterKeys.isEmpty {
                // Nothing to show yet; the note below says why.
            } else if sortedHeaterKeys.count > 2 || !fill || compact {
                // Compact rows; in the one-screen layout they scroll if they don't fit.
                let rows = VStack(spacing: 8) {
                    ForEach(sortedHeaterKeys, id: \.self) { key in
                        HeatTile(session: session, key: key, data: session.heaters[key] ?? TemperatureData(), compact: true)
                    }
                }
                if fill {
                    ScrollView { rows }.frame(maxHeight: .infinity, alignment: .top)
                } else {
                    rows
                }
            } else {
                ForEach(sortedHeaterKeys, id: \.self) { key in
                    HeatTile(session: session, key: key, data: session.heaters[key] ?? TemperatureData())
                        .frame(maxHeight: .infinity)
                }
            }
            if sortedHeaterKeys.isEmpty {
                Text("Temperatures appear once the printer is connected.")
                    .font(Typeface.body).foregroundStyle(Palette.dust)
                    .frame(maxWidth: .infinity, minHeight: 80, maxHeight: fill ? .infinity : nil)
                    .machined()
            }
        }
    }

    private var sortedHeaterKeys: [String] {
        session.heaters.filter { HeaterKind(key: $0.key).isHeater && $0.value.actual != nil }.keys.sorted { rank($0) < rank($1) }
    }

    private func rank(_ key: String) -> Int {
        switch HeaterKind(key: key) {
        case .tool(let index): index
        case .bed: 100
        case .chamber: 101
        case .ambient, .probe, .other: 102
        }
    }
}

private struct CameraSlotKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

// MARK: - Camera with cinema mode

struct CinemaCamera: View {
    let session: PrinterSession
    let filament: Color
    @Binding var cinema: Bool
    @State private var hovering = false

    var body: some View {
        CameraStage(session: session)
            .overlay(alignment: .bottom) {
                if cinema { CinemaHUD(session: session, filament: filament) }
            }
            .overlay(alignment: .bottomTrailing) {
                // Always in the hierarchy so the keyboard shortcuts work; only visible on hover or in cinema.
                HStack(spacing: 8) {
                if session.webcamStreamURL != nil && PictureInPicture.shared.sessionID != session.instance.id {
                    Button {
                        cinema = false
                        PictureInPicture.shared.show(session, filament: filament)
                    } label: {
                        Image(systemName: "pip.enter")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(.black.opacity(0.55)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("p", modifiers: [])
                    .help("Picture in picture (P): a small camera window that stays on top")
                }
                Button {
                    withAnimation(.smooth(duration: 0.35)) { cinema.toggle() }
                } label: {
                    Image(systemName: cinema ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(cinema ? KeyboardShortcut(.escape, modifiers: []) : KeyboardShortcut("f", modifiers: []))
                .help(cinema ? "Exit cinema mode (Esc)" : "Cinema mode (F)")
                }
                .padding(cinema ? 20 : 14)
                .opacity(hovering || cinema ? 1 : 0)
            }
            .overlay(alignment: .topTrailing) {
                if session.webcamStreamURL != nil, session.camera.frame != nil {
                    SnapshotMenu(session: session)
                        .padding(cinema ? 20 : 12)
                        .opacity(hovering || cinema ? 1 : 0)
                        .allowsHitTesting(hovering || cinema)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { withAnimation(.smooth(duration: 0.35)) { cinema.toggle() } }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Status strip laid over the camera in cinema mode.
struct CinemaHUD: View {
    let session: PrinterSession
    let filament: Color

    var body: some View {
        let running = session.flags.isJobActive
        HStack(alignment: .bottom, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(running ? SlicedName(session.job?.file.displayName ?? "").title : session.stateText)
                    .font(Typeface.text(20, .demibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if running, let fraction = session.progress?.fraction {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18))
                            Capsule().fill(filament).frame(width: geo.size.width * fraction)
                        }
                    }
                    .frame(height: 5)
                    .frame(maxWidth: 520)
                }
            }
            Spacer()
            if running {
                hud("\(Int((session.progress?.fraction ?? 0) * 100))%", "done")
                hud(Fmt.duration(session.progress?.printTimeLeft), "left")
                hud(Fmt.eta(session.progress?.printTimeLeft), "finishes")
            }
            ForEach(session.heaters.filter { HeaterKind(key: $0.key).isHeater && $0.value.actual != nil }.keys.sorted(), id: \.self) { key in
                hud(Fmt.temp(session.heaters[key]?.actual), HeaterKind(key: key).displayName.lowercased())
            }
            Color.clear.frame(width: 40, height: 1)
        }
        .padding(.horizontal, 28)
        .padding(.top, 60)
        .padding(.bottom, 24)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }

    private func hud(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Typeface.number(26)).foregroundStyle(.white)
            Text(label).font(Typeface.caption).foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - Sensors

// MARK: - Printing

struct JobPanel: View {
    @Environment(\.openWindow) private var openWindow
    let session: PrinterSession
    let filament: Color
    @Binding var tab: StageTab
    @State private var showingObjects = false

    var body: some View {
        let flags = session.flags
        let fraction = session.progress?.fraction ?? 0
        let name = SlicedName(session.job?.file.displayName ?? "")
        let entry = session.fileEntry(for: session.job?.file)

        HStack(alignment: .top, spacing: 24) {
            LayerStack(fraction: fraction, filament: filament, active: flags.printing)
                .frame(width: 84)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(flags.cancelling ? "Stopping" : flags.paused || flags.pausing ? "Paused" : "Now printing")
                            .font(Typeface.caption)
                            .foregroundStyle(flags.cancelling ? Palette.hot : flags.paused ? Palette.warm : Palette.faint)
                        Text(name.title)
                            .font(Typeface.text(21, .demibold))
                            .foregroundStyle(Palette.paper)
                            .lineLimit(2)
                        if !name.tags.isEmpty { TagRow(tags: name.tags) }

                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(Int(fraction * 100))")
                                .font(Typeface.number(76))
                                .foregroundStyle(Palette.paper)
                                .contentTransition(.numericText(value: fraction))
                            Text("%").font(Typeface.number(26)).foregroundStyle(Palette.faint)
                            if let z = session.currentZ, z > 0 {
                                Text(String(format: "Z %.2f mm", z)).font(Typeface.number(15)).foregroundStyle(filament).padding(.leading, 14)
                            }
                        }
                        .padding(.top, 4)

                        if let layers = layerLine {
                            Text(layers)
                                .font(Typeface.number(15))
                                .foregroundStyle(Palette.dust)
                                .lineLimit(1)
                                .contentTransition(.numericText())
                        }

                        if flags.cancelling {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(session.isWaitingForHeaters
                                      ? "OctoPrint is stopping the print, but the printer is waiting for its heaters and won't respond until that finishes."
                                      : "OctoPrint is stopping the print and running its cancel routine.",
                                      systemImage: "stop.circle.fill")
                                    .font(Typeface.caption)
                                    .foregroundStyle(Palette.hot)
                                    .fixedSize(horizontal: false, vertical: true)
                                if session.isWaitingForHeaters {
                                    Button { session.interruptHeating() } label: { Label("Interrupt heating", systemImage: "bolt.slash.fill") }
                                        .buttonStyle(.plate(Palette.hot))
                                        .controlSize(.small)
                                        .help("Sends M108, which breaks the firmware out of its heating wait so the cancel can finish")
                                }
                            }
                        } else if let warming = warmingUp {
                            Label(warming, systemImage: "flame.fill")
                                .font(Typeface.caption)
                                .foregroundStyle(Palette.warm)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if entry?.thumbnail != nil {
                        FileThumbnail(file: entry, client: session.client, tint: filament, radius: 14)
                            .frame(width: 150, height: 150)
                    }
                }

                Spacer(minLength: 0)

                if !flags.cancelling {
                    HStack(spacing: 10) {
                        RateStepper(title: "Speed", value: session.feedRate, step: 5, range: 50...200,
                                    help: "Print speed (M220). Changes take effect straight away.") { session.setFeedRate($0) }
                        RateStepper(title: "Flow", value: session.flowRate, step: 1, range: 75...125,
                                    help: "Extrusion flow (M221). Small changes help with over or under extrusion.") { session.setFlowRate($0) }
                    }
                }

                HStack(alignment: .bottom) {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                        GridRow {
                            stat("Time left", Fmt.duration(session.progress?.printTimeLeft), big: true)
                            stat("Done at", Fmt.eta(session.progress?.printTimeLeft), big: true)
                        }
                        GridRow {
                            stat("Printing for", Fmt.duration(session.progress?.printTime))
                            stat("Filament", Fmt.filament(session.job?.filament.values.compactMap(\.length).reduce(0, +)))
                        }
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 8) {
                    let objects = session.printObjects.filter { !$0.ignored }
                    if session.hasCancelObject, objects.count > 1 {
                        Button { showingObjects = true } label: {
                            Label("\(objects.count) objects", systemImage: "square.on.square.dashed")
                                .lineLimit(1)
                        }
                        .buttonStyle(.plateQuiet)
                        .fixedSize()
                        .help("Stop one part if it fails, and let the rest finish")
                    }
                    if let entry {
                        Button {
                            openWindow(id: "gcode-preview",
                                       value: GCodePreviewRequest(instanceID: session.instance.id, origin: entry.origin.rawValue, path: entry.path))
                        } label: {
                            Label("Live preview", systemImage: "square.stack.3d.up")
                                .lineLimit(1)
                        }
                        .buttonStyle(.plateQuiet)
                        .fixedSize()
                        .help("Watch the print build up layer by layer in 3D")
                    }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .machined(radius: 20)
        .sheet(isPresented: $showingObjects) { CancelObjectsSheet(session: session, filament: filament) }
    }

    /// "Layer 71 of 120, about 1 min each", from the DisplayLayerProgress plugin.
    private var layerLine: String? {
        guard let progress = session.layerProgress, progress.hasLayers,
              let current = progress.currentLayer, let total = progress.totalLayers else { return nil }
        var line = "Layer \(current) of \(total)"
        if let average = progress.averageLayerDuration, average > 0 {
            line += ", about \(Fmt.duration(average)) each"
        }
        return line
    }

    /// While the print is waiting for heaters (start of a job), say so; "0%" alone looks stuck.
    private var warmingUp: String? {
        guard (session.progress?.completion ?? 0) < 1 else { return nil }
        let heating = session.heaters
            .filter { HeaterKind(key: $0.key).isHeater }
            .sorted { $0.key > $1.key } // "tool0" before "bed"
            .compactMap { key, data -> String? in
                guard let actual = data.actual, let target = data.target, target > 0, actual < target - 3 else { return nil }
                return "\(HeaterKind(key: key).displayName.lowercased()) \(Fmt.deg(actual)) → \(Fmt.deg(target))"
            }
        return heating.isEmpty ? nil : "Heating up: " + heating.joined(separator: ", ")
    }

    private func stat(_ title: String, _ value: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Typeface.caption).foregroundStyle(Palette.faint).lineLimit(1)
            Text(value)
                .font(Typeface.number(big ? 26 : 18))
                .foregroundStyle(Palette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Ready (not printing): quick file picker

struct ReadyPanel: View {
    let session: PrinterSession
    let filament: Color
    @Binding var tab: StageTab
    /// Set when the user asks to pick a different file while one is open.
    @State private var browsing = false

    private var opened: FileEntry? {
        session.job?.hasFile == true ? session.fileEntry(for: session.job?.file) : nil
    }

    var body: some View {
        Group {
            if let opened, !browsing {
                OpenedFilePanel(session: session, file: opened, filament: filament) { browsing = true }
            } else {
                FileBrowserPanel(session: session, filament: filament, tab: $tab, openedID: opened?.id) {
                    browsing = false
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .machined(radius: 20)
        // Opening a file (here, in the Files tab or in OctoPrint itself) shows it straight away.
        .onChange(of: session.job?.file.path) { browsing = false }
    }
}

/// The open (selected) file, ready to print: everything you'd check first, and a big Print button.
struct OpenedFilePanel: View {
    @Environment(\.openWindow) private var openWindow
    let session: PrinterSession
    let file: FileEntry
    let filament: Color
    let chooseAnother: () -> Void
    @State private var previewing = false

    var body: some View {
        let name = SlicedName(file.displayName)
        VStack(alignment: .leading, spacing: 14) {
            // What it is, and what you can do with it, always in view.
            HStack(alignment: .top, spacing: 16) {
                FileThumbnail(file: file, client: session.client, tint: filament, radius: 14)
                    .frame(width: 104, height: 104)
                    .contentShape(Rectangle())
                    .onTapGesture { previewing = true }
                    .popover(isPresented: $previewing) {
                        FilePreview(file: file, client: session.client, filament: filament, canOpen: false,
                                    preview: { previewing = false; openPreview() }, open: {})
                    }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ready to print").font(Typeface.caption).foregroundStyle(Palette.faint)
                    Text(name.title)
                        .font(Typeface.text(20, .demibold))
                        .foregroundStyle(Palette.paper)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if !name.tags.isEmpty { TagRow(tags: name.tags) }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }

            if !session.canControl, let blocker = session.controlBlocker {
                Text(blocker).font(Typeface.caption).foregroundStyle(Palette.warm).lineLimit(2)
            }
            // Full labels when they fit; shorter ones in tight spaces (never wrapped).
            ViewThatFits(in: .horizontal) {
                actions(print: "Print", preview: "Preview", another: "Choose another file")
                actions(print: "Print", preview: "Preview", another: "Other file")
                actions(print: "Print", preview: nil, another: nil)
            }

            Divider().overlay(Palette.edge.opacity(0.6))

            // The details scroll when the panel is short.
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                    GridRow {
                        stat("Print time", Fmt.duration(file.gcodeAnalysis?.estimatedPrintTime), big: true)
                        stat("Filament", Fmt.filament(file.gcodeAnalysis?.totalFilamentLength), big: true)
                    }
                    GridRow {
                        stat("Model size", modelSize)
                        stat("Added", file.date?.formatted(.relative(presentation: .named)) ?? "–")
                    }
                    if let prints = file.prints, (prints.success ?? 0) + (prints.failure ?? 0) > 0 {
                        GridRow {
                            stat("Printed before", "\(prints.success ?? 0) ok, \(prints.failure ?? 0) failed")
                            stat("Last time", prints.last?.success.map { $0 ? "Finished" : "Failed or stopped" } ?? "–")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
        .padding(20)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func actions(print: String, preview: String?, another: String?) -> some View {
        HStack(spacing: 8) {
            Button { session.jobCommand(.start) } label: {
                Label(print, systemImage: "play.fill").font(Typeface.text(14, .demibold)).lineLimit(1)
            }
            .buttonStyle(.plate(filament))
            .disabled(!session.canControl)
            Button(action: openPreview) {
                if let preview {
                    Label(preview, systemImage: "square.stack.3d.up").font(Typeface.text(14, .demibold)).lineLimit(1)
                } else {
                    Image(systemName: "square.stack.3d.up")
                }
            }
            .buttonStyle(.plateQuiet)
            .help("Preview the G-code")
            Button(action: chooseAnother) {
                if let another {
                    Label(another, systemImage: "square.grid.2x2").font(Typeface.text(14, .demibold)).lineLimit(1)
                } else {
                    Image(systemName: "square.grid.2x2")
                }
            }
            .buttonStyle(.plateQuiet)
            .help("Choose another file")
        }
        .fixedSize()
    }

    private func openPreview() {
        openWindow(id: "gcode-preview", value: GCodePreviewRequest(instanceID: session.instance.id, origin: file.origin.rawValue, path: file.path))
    }

    private var modelSize: String {
        guard let d = file.gcodeAnalysis?.dimensions, let w = d.width, let dp = d.depth, let h = d.height else { return "–" }
        return "\(Fmt.number(w)) × \(Fmt.number(dp)) × \(Fmt.number(h)) mm"
    }

    private func stat(_ title: String, _ value: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Typeface.caption).foregroundStyle(Palette.faint).lineLimit(1)
            Text(value)
                .font(Typeface.number(big ? 26 : 16))
                .foregroundStyle(Palette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// All G-code on the printer as cards, alphabetical, with an instant name filter.
struct FileBrowserPanel: View {
    let session: PrinterSession
    let filament: Color
    @Binding var tab: StageTab
    /// The file OctoPrint currently has open, if any.
    let openedID: FileEntry.ID?
    let back: () -> Void
    @State private var filter = ""

    private var canGoBack: Bool { openedID != nil }

    private var files: [FileEntry] {
        let all = alphabetical(flatten(session.files).filter(\.isMachineCode))
        guard !filter.isEmpty else { return all }
        // Match the readable title only; slicer tags like "PETG" are in every filename and would match everything.
        return all.filter { SlicedName($0.displayName).title.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if canGoBack {
                    Button(action: back) { Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.dust)
                        .help("Back to the open file")
                }
                Text("Choose a file").font(Typeface.subhead).foregroundStyle(Palette.paper).lineLimit(1).fixedSize()
                if !session.canControl {
                    Text(session.isPrinterConnecting ? "Connecting…" : session.isPrinterConnected ? "Printer busy" : "Printer not connected")
                        .font(Typeface.caption).foregroundStyle(Palette.warm)
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Palette.faint)
                    TextField("Filter by name", text: $filter)
                        .textFieldStyle(.plain)
                        .font(Typeface.body)
                    if !filter.isEmpty {
                        Button { filter = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.faint) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 100, idealWidth: 220, maxWidth: 220)
                .background(Capsule().fill(Palette.graphite))
                .overlay(Capsule().strokeBorder(Palette.edge, lineWidth: 1))
                Button("All files") { tab = .files }
                    .buttonStyle(.plain)
                    .font(Typeface.bodyStrong)
                    .foregroundStyle(Palette.accent)
                    .fixedSize()
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(files) { file in
                        // Re-opening the already-open file changes nothing on the server, so just go back to it.
                        FileCard(session: session, file: file, filament: filament) {
                            if file.id == openedID { back() } else { session.select(file, print: false) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .overlay {
                if files.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: filter.isEmpty ? "tray" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 26, weight: .light)).foregroundStyle(Palette.faint)
                        Text(filter.isEmpty ? "No G-code on this printer yet" : "No files match “\(filter)”")
                            .font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                        Text(filter.isEmpty ? "Drop files on the Files tab to upload them." : "Try part of the name, or clear the filter.")
                            .font(Typeface.caption).foregroundStyle(Palette.dust)
                    }
                }
            }
        }
    }

    private func flatten(_ files: [FileEntry]) -> [FileEntry] {
        files.flatMap { [$0] + flatten($0.children ?? []) }
    }
}

/// A file as a card: big thumbnail, readable title, slicer tags. Clicking the title (or Open on hover) opens it;
/// clicking the thumbnail shows a larger preview.
struct FileCard: View {
    @Environment(\.openWindow) private var openWindow
    let session: PrinterSession
    let file: FileEntry
    let filament: Color
    let onOpen: () -> Void
    @State private var hovering = false
    @State private var previewing = false

    var body: some View {
        let name = SlicedName(file.displayName)
        VStack(alignment: .leading, spacing: 10) {
            FileThumbnail(file: file, client: session.client, tint: filament, radius: 12)
                .aspectRatio(4 / 3, contentMode: .fit)
                .contentShape(Rectangle())
                .onTapGesture { previewing = true }
                .popover(isPresented: $previewing, arrowEdge: .bottom) {
                    FilePreview(file: file, client: session.client, filament: filament, canOpen: session.canControl,
                                preview: {
                                    previewing = false
                                    openWindow(id: "gcode-preview", value: GCodePreviewRequest(instanceID: session.instance.id, origin: file.origin.rawValue, path: file.path))
                                }) {
                        previewing = false
                        open()
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if hovering {
                        Button("Open", action: open)
                            .buttonStyle(.plate(filament))
                            .controlSize(.small)
                            .fixedSize()
                            .disabled(!session.canControl)
                            .padding(8)
                            .transition(.opacity)
                    }
                }

            Button(action: open) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(name.title)
                        .font(Typeface.text(14, .demibold))
                        .foregroundStyle(hovering && session.canControl ? filament : Palette.paper)
                        .lineLimit(1)
                    if !name.tags.isEmpty { TagRow(tags: name.tags) }
                    HStack(spacing: 10) {
                        Label(Fmt.duration(file.gcodeAnalysis?.estimatedPrintTime), systemImage: "clock")
                        Label(Fmt.filament(file.gcodeAnalysis?.totalFilamentLength), systemImage: "scribble")
                    }
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!session.canControl)
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(hovering ? Palette.extrusionHi : Palette.graphite.opacity(0.6))
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(file.date.map { "Added \($0.formatted(.relative(presentation: .named)))" } ?? file.name)
    }

    private func open() { onOpen() }
}

/// "gridfinity_bins_3x2_PLA.gcode" → "gridfinity bins 3x2 PLA"; slicer suffixes are dropped.
func prettyName(_ name: String?) -> String? {
    name.map { SlicedName($0).title }
}

/// Temperature presets saved in OctoPrint (e.g. "Prusament PETG"), chosen from a dropdown, plus Cool down.
struct PresetPanel: View {
    let session: PrinterSession
    @AppStorage private var chosen: String
    @State private var choosing = false

    init(session: PrinterSession) {
        self.session = session
        // Remember the last preset per printer.
        _chosen = AppStorage(wrappedValue: "", "preset.\(session.instance.id.uuidString)")
    }

    private var presets: [(name: String, extruder: Double, bed: Double)] { session.temperaturePresets }
    /// Nothing is chosen until you pick a preset, so the panel never suggests temperatures you didn't ask for.
    private var selected: (name: String, extruder: Double, bed: Double)? {
        presets.first { $0.name == chosen }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presets").font(Typeface.bodyStrong).foregroundStyle(Palette.dust)

            if presets.isEmpty {
                Text("No temperature presets saved in OctoPrint.").font(Typeface.caption).foregroundStyle(Palette.faint)
            } else {
                Button { choosing.toggle() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(selected?.name ?? "Choose a preset")
                                .font(Typeface.bodyStrong)
                                .foregroundStyle(selected == nil ? Palette.dust : Palette.paper)
                            if let selected {
                                Text("Hotend \(Fmt.deg(selected.extruder)), bed \(Fmt.deg(selected.bed))")
                                    .font(Typeface.number(12)).foregroundStyle(Palette.faint)
                            } else {
                                Text("\(presets.count) saved in OctoPrint")
                                    .font(Typeface.caption).foregroundStyle(Palette.faint)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.faint)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.graphite))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(choosing ? Palette.accent : Palette.edge, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $choosing, arrowEdge: .bottom) {
                    PresetList(presets: presets, chosen: selected?.name) { name in
                        chosen = name
                        choosing = false
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    if let selected { session.applyPreset(extruder: selected.extruder, bed: selected.bed) }
                } label: { Label("Heat", systemImage: "flame.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.plate(Palette.heat(selected?.extruder)))
                    .disabled(selected == nil)
                    .help(selected == nil ? "Choose a preset first" : "Heat the hotend and bed to this preset")
                Button { session.coolDown() } label: { Label("Cool down", systemImage: "snowflake").frame(maxWidth: .infinity) }
                    .buttonStyle(.plateQuiet)
            }
            .controlSize(.small)
        }
        .padding(14)
        .machined(radius: 14)
        .disabled(!session.isPrinterConnected)
    }
}

/// The preset choices, drawn in the app's own style rather than as a system menu.
struct PresetList: View {
    let presets: [(name: String, extruder: Double, bed: Double)]
    let chosen: String?
    let pick: (String) -> Void
    @State private var hovered: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(presets, id: \.name) { preset in
                    Button { pick(preset.name) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.accent)
                                .opacity(preset.name == chosen ? 1 : 0)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.name).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                                Text("Hotend \(Fmt.deg(preset.extruder)), bed \(Fmt.deg(preset.bed))")
                                    .font(Typeface.number(12)).foregroundStyle(Palette.faint)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(hovered == preset.name ? Palette.extrusionHi : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 ? preset.name : (hovered == preset.name ? nil : hovered) }
                }
            }
            .padding(6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 260)
        .frame(maxHeight: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.extrusion)
        .presentationBackground(Palette.extrusion)
    }
}

/// A small tag at the top of an event marker.
struct EventFlag: View {
    let kind: ChartEvent.Kind
    let color: Color

    var body: some View {
        Text(kind.label)
            .font(Typeface.text(10, .demibold))
            .foregroundStyle(kind == .connected || kind == .disconnected ? Palette.graphite : .white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color))
    }
}

struct ChartTooltip: View {
    let readout: HoverReadout

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(readout.time, format: .dateTime.hour().minute().second())
                .font(Typeface.number(12))
                .foregroundStyle(Palette.faint)
            ForEach(readout.values, id: \.heater) { value in
                let name = HeaterKind(key: value.heater).displayName
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(seriesColor(name)).frame(width: 7, height: 7)
                    Text(name).font(Typeface.caption).foregroundStyle(Palette.dust)
                    Spacer(minLength: 12)
                    Text(Fmt.temp(value.actual)).font(Typeface.number(15)).foregroundStyle(Palette.paper)
                    Text((value.target ?? 0) > 0 ? "→ \(Fmt.deg(value.target))" : "off")
                        .font(Typeface.number(12)).foregroundStyle(Palette.faint)
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
            ForEach(readout.events) { event in
                Label("\(event.kind.label) at \(event.time.formatted(.dateTime.hour().minute().second()))", systemImage: "flag.fill")
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(10)
        .frame(minWidth: 190)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.extrusionHi))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.edge, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

/// Chart series colour per heater name, shared by the chart and its header readings.
func seriesColor(_ name: String) -> Color {
    switch name {
    case "Bed": return Palette.cold
    case "Chamber": return Palette.ready
    case "Hotend": return Palette.hot
    default:
        // "Hotend 2", "Hotend 3", ...: each gets its own colour.
        guard name.hasPrefix("Hotend "), let number = Int(name.dropFirst(7)) else { return Palette.dust }
        let extra = [Palette.warm, Color(hex: 0xE86A92), Color(hex: 0x8F7CFF), Color(hex: 0xF29E4C), Color(hex: 0x4FD1C5)]
        return extra[(number - 2) % extra.count]
    }
}

/// Live readings shown in the temperature chart's header.
struct CurrentReadings: View {
    let session: PrinterSession

    /// Read-only sensors (ambient, probe, …). One that reads exactly 0° isn't fitted, so it's hidden.
    private var sensorKeys: [String] {
        session.heaters.filter { !HeaterKind(key: $0.key).isHeater && ($0.value.actual ?? 0) != 0 }.keys.sorted()
    }

    var body: some View {
        HStack(spacing: 20) {
            ForEach(sensorKeys, id: \.self) { key in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(HeaterKind(key: key).displayName).font(Typeface.caption).foregroundStyle(Palette.faint)
                    Text(Fmt.temp(session.heaters[key]?.actual)).font(Typeface.number(14)).foregroundStyle(Palette.dust)
                }
            }
            if !sensorKeys.isEmpty {
                Rectangle().fill(Palette.edge).frame(width: 1, height: 14)
            }
            ForEach(session.heaters.filter { HeaterKind(key: $0.key).isHeater && $0.value.actual != nil }.keys.sorted(), id: \.self) { key in
                let data = session.heaters[key]
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(seriesColor(HeaterKind(key: key).displayName)).frame(width: 7, height: 7)
                    Text(HeaterKind(key: key).displayName).font(Typeface.caption).foregroundStyle(Palette.faint)
                    Text(Fmt.temp(data?.actual)).font(Typeface.number(17)).foregroundStyle(Palette.paper)
                    if let target = data?.target, target > 0 {
                        Text("→ \(Fmt.deg(target))").font(Typeface.number(13)).foregroundStyle(Palette.dust)
                    }
                }
            }
        }
    }
}

/// Shown when OctoPrint is reachable but its USB/serial link to the printer is down.
struct PrinterOfflineBanner: View {
    let session: PrinterSession
    @Binding var tab: StageTab

    private var reportedError: String? {
        guard let error = session.state?.error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty else { return nil }
        return error
    }

    private var afterError: Bool { session.printerFault || reportedError != nil }

    private func plainReason(_ reason: String?) -> String? {
        switch reason {
        case "autodetect": "OctoPrint couldn't find the printer on any USB port. Check the printer is switched on and its USB cable is plugged in, then connect."
        case "timeout": "The printer stopped replying to OctoPrint. Check it's still switched on, then connect again."
        default: nil
        }
    }

    /// What OctoPrint recorded the last time the connection failed, when the main text doesn't already say it.
    private var lastError: String? {
        guard let info = session.printerError, !info.isEmpty, info.error != reportedError else { return nil }
        switch info.reason {
        case "autodetect": return "Last attempt: OctoPrint couldn't find the printer on any USB port."
        case "timeout": return "Last attempt: the printer stopped replying to OctoPrint."
        case "firmware": return "The printer's firmware reported: \(info.error)"
        default: return "OctoPrint reported: \(info.error)"
        }
    }

    private var explanation: String {
        if let reportedError {
            // OctoPrint's wording for the common cases is technical; say it plainly instead.
            if session.printerError?.error == reportedError, let plain = plainReason(session.printerError?.reason) { return plain }
            return reportedError
        }
        let port = session.connection?.current.port ?? session.connection?.options.portPreference
        if session.isPrinterConnecting {
            return "OctoPrint is opening the serial port and waiting for the printer to reply. This usually takes a few seconds."
        }
        if afterError {
            return "OctoPrint tried to talk to the printer\(port.map { " on \($0)" } ?? "") and got no reply. Check the printer is switched on and its USB cable is plugged in, then connect."
        }
        return "OctoPrint is running, but it isn't connected to the printer. Switch the printer on, then connect."
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: afterError ? "exclamationmark.triangle.fill" : "powerplug.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(afterError ? Palette.hot : Palette.warm)
                .frame(width: 44, height: 44)
                .background(Circle().fill((afterError ? Palette.hot : Palette.warm).opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                Text(session.isPrinterConnecting ? "Connecting to the printer…" : afterError ? "The printer stopped answering" : "The printer isn't connected")
                    .font(Typeface.subhead).foregroundStyle(Palette.paper)
                Text(explanation)
                    .font(Typeface.body).foregroundStyle(Palette.dust)
                    .fixedSize(horizontal: false, vertical: true)
                if let lastError, !session.isPrinterConnecting {
                    Label(lastError, systemImage: "info.circle")
                        .font(Typeface.caption).foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.top, 3)
                }
            }
            Spacer()
            Button("Show console") { tab = .console }.buttonStyle(.plateQuiet)
            if session.isPrinterConnecting {
                ProgressView().controlSize(.small).tint(Palette.accent)
            } else {
                Button { session.connectPrinter() } label: { Label("Connect", systemImage: "bolt.horizontal.fill") }
                    .buttonStyle(.plate)
            }
        }
        .padding(18)
        .machined(radius: 16)
    }
}

/// A compact "− Speed 100% +" control for adjusting a running print.
struct RateStepper: View {
    let title: String
    let value: Double
    let step: Double
    let range: ClosedRange<Double>
    let help: String
    let apply: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            nudge("minus", by: -step)
            Button { apply(100) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title).font(Typeface.caption).foregroundStyle(Palette.faint)
                    Text("\(Int(value))%")
                        .font(Typeface.number(16))
                        .foregroundStyle(value == 100 ? Palette.paper : Palette.warm)
                        .contentTransition(.numericText(value: value))
                        .frame(minWidth: 42)
                }
                .padding(.horizontal, 4)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(value == 100 ? help : "\(help) Click to go back to 100%.")
            nudge("plus", by: step)
        }
        .background(Capsule().fill(Palette.graphite))
        .overlay(Capsule().strokeBorder(Palette.edge, lineWidth: 1))
        .fixedSize()
        .animation(.snappy, value: value)
    }

    private func nudge(_ symbol: String, by amount: Double) -> some View {
        let next = min(range.upperBound, max(range.lowerBound, value + amount))
        return Button { apply(Int(next)) } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.dust)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(next == value)
    }
}
