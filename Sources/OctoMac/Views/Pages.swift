import OctoPrintKit
import SwiftUI
import UniformTypeIdentifiers

/// A titled panel on the stage.
struct StagePanel<Content: View>: View {
    let title: String
    var detail: String?
    var fills = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelHeading(title: title, detail: detail)
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .topLeading)
        .machined(radius: 20)
    }
}

/// Explains why controls are disabled.
struct StageNotice: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(Typeface.bodyStrong)
            .foregroundStyle(Palette.warm)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Palette.warm.opacity(0.12)))
    }
}

// MARK: - Move

struct MovePage: View {
    let session: PrinterSession
    @AppStorage("jogStep") private var step = 10.0
    @AppStorage("extrudeAmount") private var extrudeAmount = 5.0
    @State private var fan = 100.0

    private let steps: [Double] = [0.1, 1, 10, 50, 100]

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !session.canControl {
                        StageNotice(text: session.flags.isJobActive
                            ? "Moving the print head is locked while a print is running. Fan and speed still work."
                            : "Connect the printer to move it.")
                    }
                    // Side by side when there's room; stacked on smaller windows.
                    if geo.size.width >= 940 {
                        HStack(alignment: .top, spacing: 20) {
                            printHead.frame(minHeight: max(560, geo.size.height - 80))
                            controls.frame(width: 420)
                        }
                    } else {
                        printHead.frame(height: 540)
                        controls
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var printHead: some View {
StagePanel(title: "Print head", detail: "Step \(Fmt.number(step)) mm", fills: true) {
    VStack(spacing: 28) {
        HStack(alignment: .center, spacing: 48) {
            xyDial
            zColumn
        }
        .frame(maxWidth: .infinity)

        HStack(spacing: 8) {
            ForEach(steps, id: \.self) { value in
                Chip(title: "\(Fmt.number(value)) mm", selected: step == value) { step = value }
            }
        }
        Button { session.home(Axis.allCases) } label: { Label("Home all axes", systemImage: "house.fill") }
            .buttonStyle(.plateQuiet)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
.frame(maxHeight: .infinity)
.disabled(!session.canControl)
    }

    private var controls: some View {
VStack(spacing: 20) {
    StagePanel(title: "Filament") {
        HStack(spacing: 10) {
            TextField("mm", value: $extrudeAmount, format: .number)
                .plateField()
                .frame(width: 80)
            Text("mm").font(Typeface.body).foregroundStyle(Palette.dust)
            Spacer()
            Button { session.extrude(-extrudeAmount) } label: { Label("Retract", systemImage: "arrow.up") }
                .buttonStyle(.plateQuiet)
            Button { session.extrude(extrudeAmount) } label: { Label("Extrude", systemImage: "arrow.down") }
                .buttonStyle(.plate)
        }
        Text("The hotend has to be hot before the printer will push filament.")
            .font(Typeface.caption).foregroundStyle(Palette.faint)
    }
    .disabled(!session.canControl)

    StagePanel(title: "Fan and speed") {
        VStack(spacing: 18) {
            dialRow("Part fan", value: $fan, range: 0...100, step: 5, unit: "%") { session.setFan(percent: fan) }
            dialRow("Print speed", value: rate(\.feedRate), range: 50...200, step: 5, unit: "%") { session.setFeedRate(Int(session.feedRate)) }
            dialRow("Flow", value: rate(\.flowRate), range: 75...125, step: 1, unit: "%") { session.setFlowRate(Int(session.flowRate)) }
        }
    }
    .disabled(!session.flags.operational)

    StagePanel(title: "Quick commands") {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            quick("Motors off", "M18", "power")
            quick("Fan off", "M107", "fan.slash")
            quick("Report position", "M114", "location")
            quick("Firmware info", "M115", "info.circle")
            quick("Bed mesh", "M420 V", "square.grid.3x3")
            quick("Save to EEPROM", "M500", "square.and.arrow.down")
        }
    }
    .disabled(!session.flags.operational)
}
    }

    private var xyDial: some View {
        ZStack {
            Circle().fill(Palette.graphite).frame(width: 300, height: 300)
            Circle().strokeBorder(Palette.edge, lineWidth: 1).frame(width: 300, height: 300)
            Circle().strokeBorder(Palette.edge.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 5])).frame(width: 190, height: 190)
            VStack(spacing: 0) {
                Button { session.jog(y: step) } label: { Image(systemName: "chevron.up") }.buttonStyle(.key).help("Y+")
                Spacer()
                Button { session.jog(y: -step) } label: { Image(systemName: "chevron.down") }.buttonStyle(.key).help("Y−")
            }
            .frame(height: 270)
            HStack(spacing: 0) {
                Button { session.jog(x: -step) } label: { Image(systemName: "chevron.left") }.buttonStyle(.key).help("X−")
                Spacer()
                Button { session.jog(x: step) } label: { Image(systemName: "chevron.right") }.buttonStyle(.key).help("X+")
            }
            .frame(width: 270)
            Button { session.home([.x, .y]) } label: { Image(systemName: "house.fill") }
                .buttonStyle(KeyButtonStyle(size: CGSize(width: 64, height: 64)))
                .help("Home X and Y")
            axisLabel("X", x: 128, y: 0)
            axisLabel("Y", x: 0, y: -128)
        }
    }

    private var zColumn: some View {
        VStack(spacing: 10) {
            Text("Z").font(Typeface.number(15)).foregroundStyle(Palette.faint)
            Button { session.jog(z: step) } label: { Image(systemName: "chevron.up.2") }.buttonStyle(.key).help("Raise Z")
            Button { session.home([.z]) } label: { Image(systemName: "house.fill") }.buttonStyle(.key).help("Home Z")
            Button { session.jog(z: -step) } label: { Image(systemName: "chevron.down.2") }.buttonStyle(.key).help("Lower Z")
        }
        .padding(14)
        .background(Capsule().fill(Palette.graphite))
        .overlay(Capsule().strokeBorder(Palette.edge, lineWidth: 1))
    }

    private func axisLabel(_ text: String, x: CGFloat, y: CGFloat) -> some View {
        Text(text).font(Typeface.number(11)).foregroundStyle(Palette.faint).offset(x: x + (x > 0 ? 8 : 0), y: y - (y < 0 ? 8 : 0))
    }

    /// Speed and flow live on the session, so the Overview's controls and these sliders agree.
    private func rate(_ keyPath: ReferenceWritableKeyPath<PrinterSession, Double>) -> Binding<Double> {
        Binding(get: { session[keyPath: keyPath] }, set: { session[keyPath: keyPath] = $0 })
    }

    private func dialRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String, apply: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.dust).frame(width: 90, alignment: .leading)
            Slider(value: value, in: range, step: step) { editing in if !editing { apply() } }
                .tint(Palette.accent)
            Text("\(Int(value.wrappedValue))\(unit)")
                .font(Typeface.number(17))
                .foregroundStyle(Palette.paper)
                .frame(width: 54, alignment: .trailing)
        }
    }

    private func quick(_ title: String, _ gcode: String, _ symbol: String) -> some View {
        Button { session.sendGcode(gcode) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(Palette.accent).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Typeface.text(12, .demibold)).foregroundStyle(Palette.paper)
                    Text(gcode).font(Typeface.number(11)).foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .machined(radius: 10, fill: Palette.graphite)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Files

struct FilesPage: View {
    @Environment(\.openWindow) private var openWindow
    let session: PrinterSession
    let filament: Color
    /// Called after a file is opened, so the stage can switch to the Overview where it's ready to print.
    var onOpened: () -> Void = {}
    @State private var folder: [String] = []
    @State private var search = ""
    @State private var importing = false
    @State private var dropTargeted = false
    @State private var creatingFolder = false
    @State private var pendingDelete: FileEntry?
    @State private var selectedFile: FileEntry.ID?
    @State private var compactList = false

    private var folderPath: String? { folder.isEmpty ? nil : folder.joined(separator: "/") }

    private var rows: [FileEntry] {
        if !search.isEmpty {
            // Match the readable title only; slicer tags like "PETG" are in every filename and would match everything.
            return alphabetical(flatten(session.files).filter { !$0.isFolder && SlicedName($0.displayName).title.localizedCaseInsensitiveContains(search) })
        }
        var level = session.files
        for name in folder {
            level = level.first { $0.isFolder && $0.name == name }?.children ?? []
        }
        return alphabetical(level)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                breadcrumbs
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
                    TextField("Find a file", text: $search).textFieldStyle(.plain).font(Typeface.body)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 140, idealWidth: 260, maxWidth: 260)
                .background(Capsule().fill(Palette.extrusion))
                .overlay(Capsule().strokeBorder(Palette.edge, lineWidth: 1))

                Button { creatingFolder = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    .buttonStyle(.plateQuiet)
                Button { importing = true } label: { Label("Upload", systemImage: "arrow.up") }
                    .buttonStyle(.plate)
            }

            VStack(spacing: 0) {
                FileHeaderRow()
                Divider().overlay(Palette.edge)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if !folder.isEmpty && search.isEmpty {
                            UpRow(parentName: folder.count > 1 ? folder[folder.count - 2] : "All files", tint: filament) { goUp() }
                                .modifier(FolderDropTarget(enabled: true, folderPath: folder.dropLast().joined(separator: "/"), tint: filament) { payload in
                                    moveDropped(payload, to: folder.dropLast().joined(separator: "/"))
                                })
                        }
                        ForEach(rows) { file in
                            FileRow(file: file, client: session.client, filament: filament, showPath: !search.isEmpty, canPrint: session.canControl,
                                    selected: selectedFile == file.id,
                                    select: { selectedFile = file.id },
                                    open: { folder.append(file.name) },
                                    openFile: {
                                        guard session.canControl else { return }
                                        session.select(file, print: false)
                                        onOpened()
                                    },
                                    preview: { openWindow(id: "gcode-preview", value: GCodePreviewRequest(instanceID: session.instance.id, origin: file.origin.rawValue, path: file.path)) },
                                    delete: { pendingDelete = file })
                                // Drag a file or folder onto a folder (or a folder name in the path above) to move it there.
                                .draggable(FileDrag.payload(for: file, instance: session.instance.id)) {
                                    FileDragPreview(file: file, client: session.client, tint: filament)
                                }
                                .modifier(FolderDropTarget(enabled: file.isFolder, folderPath: file.path, tint: filament) { payload in
                                    moveDropped(payload, to: file.path)
                                })
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                // Right-click on empty space (rows have their own menus).
                .contextMenu {
                    Button("New folder…") { creatingFolder = true }
                    Button("Upload files…") { importing = true }
                    if !folder.isEmpty {
                        Divider()
                        Button("Back to \(folder.count > 1 ? folder[folder.count - 2] : "All files")") { goUp() }
                    }
                }
                .overlay {
                    if rows.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray").font(.system(size: 28, weight: .light)).foregroundStyle(Palette.faint)
                            Text(search.isEmpty ? "This folder is empty" : "No files match “\(search)”")
                                .font(Typeface.subhead).foregroundStyle(Palette.paper)
                            Text("Drop G-code here to upload it.").font(Typeface.body).foregroundStyle(Palette.dust)
                        }
                    }
                }
                Divider().overlay(Palette.edge)
                HStack {
                    Text("\(flatten(session.files).filter { !$0.isFolder }.count) files")
                    Spacer()
                    if let free = session.freeSpace { Text("\(Fmt.bytes(free)) free on the Pi") }
                }
                .font(Typeface.caption)
                .foregroundStyle(Palette.faint)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .onGeometryChange(for: Bool.self) { $0.size.width < 820 } action: { compactList = $0 }
            .environment(\.filesCompact, compactList)
            .machined(radius: 20)
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .background(RoundedRectangle(cornerRadius: 20).fill(Palette.accent.opacity(0.08)))
                        .overlay(Label("Drop to upload to \(folder.last ?? "All files")", systemImage: "arrow.up.doc")
                            .font(Typeface.subhead).foregroundStyle(Palette.accent))
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                session.upload(urls, folder: folderPath)
                return !urls.isEmpty
            } isTargeted: { dropTargeted = $0 }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.uploadTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { session.upload(urls, folder: folderPath) }
        }
        .sheet(isPresented: $creatingFolder) {
            NameSheet(title: "New folder", placeholder: "Folder name", confirmTitle: "Create folder") { name in
                session.createFolder(name, in: folderPath)
            }
        }
        .sheet(item: $pendingDelete) { file in
            ConfirmSheet(symbol: "trash", title: file.isFolder ? "Delete this folder?" : "Delete this file?",
                         message: file.isFolder
                            ? "The folder and everything in it will be deleted from the printer. This can't be undone."
                            : "The file will be deleted from the printer. This can't be undone.",
                         confirmTitle: "Delete", onConfirm: { session.delete(file) }) {
                FileSummaryCard(file: file, client: session.client, tint: filament)
            }
        }
    }

    private func goUp() {
        guard !folder.isEmpty else { return }
        folder.removeLast()
        search = ""
    }

    private var breadcrumbs: some View {
        HStack(spacing: 6) {
            Button(action: goUp) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(folder.isEmpty ? Color.clear : Palette.extrusion))
                    .overlay(Circle().strokeBorder(folder.isEmpty ? Color.clear : Palette.edge, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(folder.isEmpty ? Palette.faint.opacity(0.4) : Palette.paper)
            .disabled(folder.isEmpty)
            .keyboardShortcut(.upArrow, modifiers: .command)
            .help("Back to the previous folder (⌘↑ or ⌘[)")
            .background {
                // Second shortcut for the same action.
                Button("", action: goUp).keyboardShortcut("[", modifiers: .command).opacity(0).allowsHitTesting(false)
            }
            .padding(.trailing, 4)
            crumb("All files", depth: 0)
            ForEach(Array(folder.enumerated()), id: \.offset) { index, name in
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.faint)
                crumb(name, depth: index + 1)
            }
        }
    }

    private func crumb(_ title: String, depth: Int) -> some View {
        let path = folder.prefix(depth).joined(separator: "/")
        return Button { folder = Array(folder.prefix(depth)); search = "" } label: {
            Text(title)
                .font(Typeface.text(17, .demibold))
                .foregroundStyle(depth == folder.count ? Palette.paper : Palette.dust)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        // Dropping on a parent in the path moves the item up to it.
        .modifier(FolderDropTarget(enabled: depth < folder.count, folderPath: path, tint: filament, radius: 8) { payload in
            moveDropped(payload, to: path)
        })
    }

    private func moveDropped(_ payload: String, to destination: String) -> Bool {
        guard let path = FileDrag.path(from: payload, instance: session.instance.id),
              let file = flatten(session.files).first(where: { $0.path == path }) else { return false }
        session.move(file, toFolder: destination)
        return true
    }

    private func flatten(_ files: [FileEntry]) -> [FileEntry] {
        files.flatMap { [$0] + flatten($0.children ?? []) }
    }

    static let uploadTypes: [UTType] = ["gcode", "gco", "g", "bgcode", "stl", "3mf"].compactMap { UTType(filenameExtension: $0) } + [.data]
}

private struct FilesCompactKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Narrow file list: fewer columns.
    var filesCompact: Bool {
        get { self[FilesCompactKey.self] }
        set { self[FilesCompactKey.self] = newValue }
    }
}

private enum FileColumns {
    static let time: CGFloat = 100
    static let filament: CGFloat = 90
    static let size: CGFloat = 90
    static let actions: CGFloat = 230
    static let compactActions: CGFloat = 170
}

/// Folders first, then files, each in Finder-style alphabetical order ("part 2" before "part 10").
func alphabetical(_ entries: [FileEntry]) -> [FileEntry] {
    entries.sorted { lhs, rhs in
        if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
}

struct FileHeaderRow: View {
    @Environment(\.filesCompact) private var compact

    var body: some View {
        HStack(spacing: 16) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 60)
            Text("Print time").frame(width: FileColumns.time, alignment: .trailing)
            if !compact {
                Text("Filament").frame(width: FileColumns.filament, alignment: .trailing)
                Text("Size").frame(width: FileColumns.size, alignment: .trailing)
            }
            Color.clear.frame(width: compact ? FileColumns.compactActions : FileColumns.actions, height: 1)
        }
        .lineLimit(1)
        .font(Typeface.caption)
        .foregroundStyle(Palette.faint)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

struct FileRow: View {
    @Environment(\.filesCompact) private var compact
    let file: FileEntry
    let client: OctoPrintClient
    let filament: Color
    let showPath: Bool
    let canPrint: Bool
    let selected: Bool
    let select: () -> Void
    let open: () -> Void
    let openFile: () -> Void
    let preview: () -> Void
    let delete: () -> Void
    @State private var hovering = false
    @State private var previewing = false

    var body: some View {
        let name = SlicedName(file.displayName)
        HStack(spacing: 16) {
            HStack(spacing: 14) {
                thumbnail
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(file.isFolder ? file.displayName : name.title)
                            .font(Typeface.text(14, .demibold))
                            .foregroundStyle(Palette.paper)
                            .lineLimit(1)
                        if !file.isFolder, let date = file.date, !compact {
                            Text("added \(date.formatted(.relative(presentation: .named)))")
                                .font(Typeface.caption)
                                .foregroundStyle(Palette.faint)
                                .lineLimit(1)
                                .fixedSize()
                                .help(date.formatted(date: .complete, time: .shortened))
                        }
                    }
                    if !file.isFolder, !name.tags.isEmpty {
                        TagRow(tags: name.tags)
                    } else if showPath || !file.isFolder {
                        Text(showPath ? file.path : file.name)
                            .font(Typeface.caption)
                            .foregroundStyle(Palette.faint)
                            .lineLimit(1)
                    }
                }
                if let success = file.prints?.last?.success {
                    StatusLamp(color: success ? Palette.ready : Palette.hot, lit: false)
                        .help(success ? "Last print finished" : "Last print failed")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            number(file.isFolder ? "" : Fmt.duration(file.gcodeAnalysis?.estimatedPrintTime), width: FileColumns.time)
            if !compact {
                number(file.isFolder ? "" : Fmt.filament(file.gcodeAnalysis?.totalFilamentLength), width: FileColumns.filament)
                number(file.isFolder ? "\(file.children?.count ?? 0) items" : file.size.map(Fmt.bytes) ?? "", width: FileColumns.size)
            }

            HStack(spacing: 8) {
                if hovering || selected {
                    if !file.isFolder {
                        Button(action: showInfo) { Image(systemName: "info.circle") }
                            .buttonStyle(.plateQuiet)
                            .help("Show file info")
                    }
                    if file.isMachineCode {
                        Button("Open", action: openFile).buttonStyle(.plate(filament)).disabled(!canPrint)
                    }
                    Button(action: delete) { Image(systemName: "trash") }
                        .buttonStyle(.plateQuiet)
                        .help("Delete")
                }
            }
            .frame(width: compact ? FileColumns.compactActions : FileColumns.actions, alignment: .trailing)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? filament.opacity(0.14) : hovering ? Palette.extrusionHi : .clear)
            if selected {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(filament.opacity(0.6), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if file.isFolder {
                Button("Open folder", action: open)
            } else {
                Button("Get info", action: showInfo)
                if file.isMachineCode {
                    Button("Preview G-code", action: preview)
                    Button("Open", action: openFile).disabled(!canPrint)
                }
            }
            Divider()
            Button("Delete…", role: .destructive, action: delete)
        }
        // Double-click shows the file's info. The single click runs alongside it rather than waiting to rule out a
        // double-click, so selection is instant.
        .onTapGesture(count: 2) { if !file.isFolder { showInfo() } }
        .simultaneousGesture(TapGesture().onEnded { file.isFolder ? open() : select() })
    }

    /// The thumbnail doubles as the way into the file's info popup.
    @ViewBuilder private var thumbnail: some View {
        let view = FileThumbnail(file: file, client: client, tint: filament, radius: 9).frame(width: 44, height: 44)
        if file.isFolder {
            view
        } else {
            Button(action: showInfo) { view }
                .buttonStyle(.plain)
                .help("Show file info")
                .popover(isPresented: $previewing, arrowEdge: .trailing) {
                    FilePreview(file: file, client: client, filament: filament, canOpen: canPrint,
                                preview: { previewing = false; preview() }) {
                        previewing = false
                        openFile()
                    }
                }
        }
    }

    private func showInfo() {
        select()
        previewing = true
    }

    private func number(_ text: String, width: CGFloat) -> some View {
        Text(text).font(Typeface.number(14)).foregroundStyle(Palette.dust).frame(width: width, alignment: .trailing)
    }
}

// MARK: - Console

struct ConsolePage: View {
    let session: PrinterSession
    /// Names of the filters that are switched on, one per line. Empty until you change something.
    @AppStorage("terminal.filters") private var enabledStorage = ""
    @AppStorage("terminal.hideTemperature") private var legacyHideTemperature = true
    @AppStorage("terminal.hideSD") private var legacyHideSD = true
    @State private var command = ""
    @State private var history: [String] = []
    @State private var historyIndex: Int?
    @State private var choosingFilters = false
    @State private var choosingHighlights = false
    /// Words and phrases to highlight, one per line.
    @AppStorage("terminal.highlights") private var highlightStorage = ""
    @AppStorage("terminal.highlightReplies") private var highlightReplies = true
    /// Commands sent from this console, so their replies can be picked out.
    @State private var sentHere: [String] = []
    @AppStorage("console.cheatSheet") private var showingCheatSheet = false
    @FocusState private var commandFocused: Bool
    /// While you're scrolled up reading, the console holds still: this is what's on screen, and new lines wait.
    @State private var frozen: [(offset: Int, element: String)]?
    @State private var frozenAt = 0
    @State private var atBottom = true
    @State private var userScrolling = false

    private var filters: [TerminalFilter] {
        var list = TerminalFilter.fromSettings(session.settings)
        // An MMU chats with the printer constantly; worth a switch of its own.
        if session.mmu != nil { list.append(TerminalFilter.mmu) }
        return list
    }

    private var enabled: Set<String> {
        if enabledStorage.isEmpty {
            // Before this setting existed there were two switches; start from those.
            var names: Set<String> = []
            if legacyHideTemperature { names.insert("Suppress temperature messages") }
            if legacyHideSD { names.insert("Suppress SD status messages") }
            return names
        }
        return Set(enabledStorage.split(separator: "\n").map(String.init).filter { $0 != "-" })
    }

    private func setEnabled(_ name: String, _ on: Bool) {
        var names = enabled
        if on { names.insert(name) } else { names.remove(name) }
        // "-" keeps the setting non-empty when everything is switched off.
        enabledStorage = (["-"] + names.sorted()).joined(separator: "\n")
    }

    private var visible: (lines: [(offset: Int, element: String)], hidden: Int) {
        let active = filters.filter { enabled.contains($0.name) }
        let all = Array(session.terminal.enumerated())
        guard !active.isEmpty else { return (all, 0) }
        let shown = all.filter { _, line in !active.contains { $0.matches(line) } }
        return (shown, all.count - shown.count)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            conversation
            if showingCheatSheet {
                GCodeReferencePanel { entry in
                    command = entry.example
                    commandFocused = true
                } close: {
                    withAnimation(.snappy) { showingCheatSheet = false }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var conversation: some View {
        let visible = self.visible
        let activeCount = filters.filter { enabled.contains($0.name) }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Printer conversation").font(Typeface.subhead).foregroundStyle(Palette.paper)
                Spacer()
                if visible.hidden > 0 {
                    Text("\(visible.hidden) of \(session.terminal.count) lines hidden")
                        .font(Typeface.caption).foregroundStyle(Palette.faint)
                }
                Button { choosingFilters.toggle() } label: {
                    Label(activeCount == 0 ? "Hide messages" : "Hiding \(activeCount) kind\(activeCount == 1 ? "" : "s")",
                          systemImage: "line.3.horizontal.decrease")
                }
                .buttonStyle(.plateQuiet)
                .controlSize(.small)
                .popover(isPresented: $choosingFilters, arrowEdge: .bottom) {
                    TerminalFilterList(filters: filters, enabled: enabled, toggle: setEnabled)
                }
                Button { choosingHighlights.toggle() } label: {
                    Label(highlightTerms.isEmpty ? "Highlight" : "Highlighting \(highlightTerms.count)", systemImage: "highlighter")
                }
                .buttonStyle(.plateQuiet)
                .controlSize(.small)
                .popover(isPresented: $choosingHighlights, arrowEdge: .bottom) {
                    ConsoleHighlightEditor(terms: highlightTerms, replies: $highlightReplies) { terms in
                        highlightStorage = terms.joined(separator: "\n")
                    }
                }
                Button { withAnimation(.snappy) { showingCheatSheet.toggle() } } label: {
                    Label("Cheat sheet", systemImage: "book.closed")
                }
                .buttonStyle(.plateQuiet)
                .controlSize(.small)
                .help("A list of common G-code commands and what they do")
            }
            .padding(20)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        let shown = frozen ?? visible.lines
                        let marks = highlights(for: shown)
                        ForEach(shown, id: \.offset) { offset, line in
                            ConsoleLine(line: line, highlight: marks[offset])
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 20)
                    .textSelection(.enabled)
                }
                .background(Palette.graphite)
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 24
                } action: { _, bottom in
                    atBottom = bottom
                    // Only your own scrolling pauses the console, not new lines arriving.
                    guard userScrolling else { return }
                    if bottom { frozen = nil } else if frozen == nil { pause(visible.lines) }
                }
                .onScrollPhaseChange { _, phase in
                    userScrolling = phase != .idle && phase != .animating
                    if phase == .idle, atBottom { frozen = nil }
                }
                .onChange(of: session.terminalReceived) { if frozen == nil { proxy.scrollTo("end", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                .overlay(alignment: .bottom) {
                    if frozen != nil {
                        let waiting = newVisibleLines
                        Button {
                            frozen = nil
                            withAnimation(.snappy) { proxy.scrollTo("end", anchor: .bottom) }
                        } label: {
                            Label(waiting > 0 ? "Paused while you read. \(waiting) new line\(waiting == 1 ? "" : "s"). Jump to latest" : "Paused while you read. Jump to latest",
                                  systemImage: "arrow.down")
                                .font(Typeface.text(12, .demibold))
                                .foregroundStyle(Palette.graphite)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Palette.accent))
                                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: frozen == nil)
            }

            HStack(spacing: 10) {
                Text("›").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(Palette.accent)
                TextField("Send a G-code command, e.g. M115", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Palette.paper)
                    .focused($commandFocused)
                    .onSubmit(send)
                    .onKeyPress(.upArrow) { recall(-1) }
                    .onKeyPress(.downArrow) { recall(1) }
                ClearFieldButton(text: $command) { commandFocused = true }
                Button("Send", action: send)
                    .buttonStyle(.plate)
                    .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty || !session.flags.operational)
            }
            .padding(16)
        }
        .machined(radius: 20)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var highlightTerms: [String] {
        highlightStorage.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Which lines to tint: your own commands and the printer's replies to them, and lines with a highlighted word.
    private func highlights(for lines: [(offset: Int, element: String)]) -> [Int: Color] {
        var marks: [Int: Color] = [:]
        let terms = highlightTerms
        var inReply = false
        for (offset, line) in lines {
            if highlightReplies {
                if line.hasPrefix("Send:") {
                    inReply = sentHere.contains(Self.normalised(line))
                    if inReply { marks[offset] = Palette.accent }
                } else if inReply, line.hasPrefix("Recv:") {
                    marks[offset] = Palette.accent
                    // The reply ends at the printer's "ok".
                    if line.dropFirst(5).trimmingCharacters(in: .whitespaces).hasPrefix("ok") { inReply = false }
                }
            }
            if let index = terms.firstIndex(where: { line.localizedCaseInsensitiveContains($0) }) {
                marks[offset] = ConsoleHighlightEditor.color(at: index)
            }
        }
        return marks
    }

    /// "Send: N123 M114*45" and "m114" both become "M114".
    static func normalised(_ line: String) -> String {
        var text = line.hasPrefix("Send:") ? String(line.dropFirst(5)) : line
        text = text.trimmingCharacters(in: .whitespaces)
        if let match = text.firstMatch(of: /^N\d+\s+/) { text.removeSubrange(match.range) }
        if let star = text.lastIndex(of: "*") { text = String(text[..<star]) }
        return text.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// Lines that arrived since pausing and would actually be shown (not hidden by a filter).
    private var newVisibleLines: Int {
        let arrived = session.terminalReceived - frozenAt
        guard arrived > 0 else { return 0 }
        let active = filters.filter { enabled.contains($0.name) }
        return session.terminal.suffix(arrived).filter { line in !active.contains { $0.matches(line) } }.count
    }

    private func pause(_ lines: [(offset: Int, element: String)]) {
        frozen = lines
        frozenAt = session.terminalReceived
    }

    private func send() {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Firmware wants capitals ("m115" becomes "M115"), except in the text of messages and file names.
        let posix = Locale(identifier: "en_US_POSIX")
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        let word = parts.first.map { $0.uppercased(with: posix) } ?? ""
        let textCommands: Set<String> = ["M117", "M118", "M23", "M28", "M30", "M32"]
        if parts.count > 1, textCommands.contains(word) {
            session.sendGcode(word + " " + parts[1])
        } else {
            session.sendGcode(trimmed.uppercased(with: posix))
        }
        if history.last != trimmed { history.append(trimmed) }
        sentHere = Array((sentHere + [Self.normalised(trimmed)]).suffix(50))
        historyIndex = nil
        command = ""
        // Show the reply.
        frozen = nil
    }

    private func recall(_ delta: Int) -> KeyPress.Result {
        guard !history.isEmpty else { return .ignored }
        let index = max(0, min(history.count, (historyIndex ?? history.count) + delta))
        historyIndex = index
        command = index < history.count ? history[index] : ""
        return .handled
    }
}

struct ConsoleLine: View {
    let line: String
    var highlight: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(direction).foregroundStyle(highlight ?? directionColor).frame(width: 14)
            Text(content).foregroundStyle(contentColor)
        }
        .font(.system(size: 12.5, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        // The tint spills slightly past the line, so highlighting never changes a line's size.
        .background {
            if let highlight {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(highlight.opacity(0.16))
                    .padding(.horizontal, -6)
                    .padding(.vertical, -1.5)
            }
        }
    }

    private var isSend: Bool { line.hasPrefix("Send:") }
    private var isRecv: Bool { line.hasPrefix("Recv:") }
    private var isError: Bool { line.localizedCaseInsensitiveContains("error") || line.contains("!!") }

    private var direction: String { isSend ? "→" : isRecv ? "←" : "•" }
    private var directionColor: Color { isError ? Palette.hot : isSend ? Palette.accent : isRecv ? Palette.cold : Palette.faint }
    private var content: String {
        if isSend || isRecv { return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        return line
    }
    private var contentColor: Color { isError ? Palette.hot : isSend ? Palette.dust : isRecv ? Palette.paper : Palette.faint }
}

// MARK: - Machine

struct MachinePage: View {
    let session: PrinterSession
    let filament: Color
    @State private var port = ""
    @State private var baudrate = 0
    @State private var profile = ""
    @State private var saveConnection = false
    @State private var pendingCommand: SystemCommand?

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 20) {
                    if geo.size.width >= 940 {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(spacing: 20) {
                                printerPanel
                                if let bed = session.bedLevel { BedMeshPanel(session: session, settings: bed) }
                                connectionPanel
                                LogsPanel(session: session)
                            }
                            VStack(spacing: 20) {
                                serverPanel
                                if let pi = session.pi { PiHealthPanel(session: session, pi: pi) }
                                if let updates = session.updates { UpdatesPanel(session: session, updates: updates) }
                                powerPanel
                            }
                        }
                    } else {
                        printerPanel
                        if let bed = session.bedLevel { BedMeshPanel(session: session, settings: bed) }
                        serverPanel
                        if let pi = session.pi { PiHealthPanel(session: session, pi: pi) }
                        connectionPanel
                        powerPanel
                        if let updates = session.updates { UpdatesPanel(session: session, updates: updates) }
                        LogsPanel(session: session)
                    }
                }
            }
        }
        .task {
            async let updates: Void = session.refreshUpdates()
            async let logs: Void = session.refreshLogs()
            async let health: Void = session.refreshHealth()
            _ = await (updates, logs, health)
        }
        .onAppear(perform: syncConnection)
        .onChange(of: session.connection) { syncConnection() }
        .sheet(item: $pendingCommand) { command in
            ConfirmSheet(symbol: symbol(for: command.action), tint: Palette.warm, title: "\(command.name)?",
                         message: (command.confirm ?? "") + " Any print in progress will stop.",
                         confirmTitle: command.name, onConfirm: { session.run(command) })
        }
    }

    private var printerPanel: some View {
        StagePanel(title: "Printer", detail: session.currentProfile?.model) {
            if let profile = session.currentProfile {
                VStack(alignment: .leading, spacing: 18) {
                    Text(profile.name).font(Typeface.title).foregroundStyle(Palette.paper)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .topLeading)], alignment: .leading, spacing: 16) {
                        if let volume = profile.volume {
                            fact("Build volume", [volume.width, volume.depth, volume.height].map { Fmt.number($0) }.joined(separator: " × "), unit: "mm")
                        }
                        fact("Nozzle", Fmt.number(profile.extruder?.nozzleDiameter ?? 0.4), unit: "mm")
                        fact("Extruders", "\(profile.extruder?.count ?? 1)", unit: nil)
                        fact("Heated bed", profile.heatedBed == true ? "Yes" : "No", unit: nil)
                    }
                    if let firmware = session.firmware {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Firmware").font(Typeface.caption).foregroundStyle(Palette.faint)
                            Text(Self.shortFirmware(firmware))
                                .font(Typeface.number(18)).foregroundStyle(Palette.paper)
                                .textSelection(.enabled)
                                .help(firmware)
                        }
                    }
                }
            } else {
                Text("Printer details appear once OctoPrint reports a profile.").font(Typeface.body).foregroundStyle(Palette.dust)
            }
        }
    }

    private var connectionPanel: some View {
        StagePanel(title: "Serial connection", detail: session.connection?.current.state) {
            if let options = session.connection?.options {
                VStack(spacing: 12) {
                    pickerRow("Port") {
                        Picker("Port", selection: $port) {
                            Text("Auto").tag("")
                            ForEach(options.ports, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    pickerRow("Baud rate") {
                        Picker("Baud rate", selection: $baudrate) {
                            Text("Auto").tag(0)
                            ForEach(options.baudrates, id: \.self) { Text(String($0)).tag($0) }
                        }
                    }
                    pickerRow("Profile") {
                        Picker("Profile", selection: $profile) {
                            Text("Default").tag("")
                            ForEach(options.printerProfiles) { Text($0.name).tag($0.id) }
                        }
                    }
                    HStack {
                        Toggle("Remember these settings", isOn: $saveConnection)
                            .toggleStyle(.switch)
                            .tint(Palette.accent)
                            .font(Typeface.body)
                            .foregroundStyle(Palette.dust)
                        Spacer()
                        if session.isPrinterConnected {
                            Button("Disconnect") { session.disconnectPrinter() }
                                .buttonStyle(.plateQuiet)
                                .disabled(session.flags.isJobActive)
                        } else {
                            Button("Connect") {
                                session.connectPrinter(ConnectRequest(port: port.isEmpty ? nil : port, baudrate: baudrate == 0 ? nil : baudrate,
                                                                      printerProfile: profile.isEmpty ? nil : profile, save: saveConnection))
                            }
                            .buttonStyle(.plate)
                        }
                    }
                    .padding(.top, 6)
                }
            } else {
                Text("Connection options load once OctoPrint is reachable.").font(Typeface.body).foregroundStyle(Palette.dust)
            }
        }
    }

    private var serverPanel: some View {
        StagePanel(title: "OctoPrint server") {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .topLeading)], alignment: .leading, spacing: 16) {
                    fact("Version", session.version?.server ?? "–", unit: nil)
                    fact("API", session.version?.api ?? "–", unit: nil)
                    fact("Signed in as", session.user ?? "–", unit: nil)
                }
                Text(session.instance.baseURL.absoluteString)
                    .font(Typeface.number(13))
                    .foregroundStyle(Palette.faint)
                    .textSelection(.enabled)
            }
        }
    }

    private var powerPanel: some View {
        StagePanel(title: "Power and restart") {
            VStack(spacing: 8) {
                if session.systemCommands.isEmpty {
                    Text("This account can't run system commands on the Pi.").font(Typeface.body).foregroundStyle(Palette.dust)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(session.systemCommands) { command in
                    HStack {
                        Image(systemName: symbol(for: command.action)).foregroundStyle(Palette.accent).frame(width: 22)
                        Text(command.name).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                        Spacer()
                        Button("Run") {
                            if command.confirm != nil { pendingCommand = command } else { session.run(command) }
                        }
                        .buttonStyle(.plateQuiet)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .machined(radius: 12, fill: Palette.graphite)
                }
            }
        }
    }

    private func fact(_ title: String, _ value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Typeface.caption).foregroundStyle(Palette.faint).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(Typeface.number(24)).foregroundStyle(Palette.paper)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(unit).font(Typeface.number(13)).foregroundStyle(Palette.faint).fixedSize() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Prusa-Firmware 3.14.1+8237_74a577bc0 based on Marlin" reads better as "Prusa-Firmware 3.14.1".
    static func shortFirmware(_ firmware: String) -> String {
        var text = firmware
        if let range = text.range(of: " based on ") { text = String(text[..<range.lowerBound]) }
        if let plus = text.firstIndex(of: "+") { text = String(text[..<plus]) }
        return text
    }

    private func pickerRow<P: View>(_ title: String, @ViewBuilder picker: () -> P) -> some View {
        HStack {
            Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.dust).frame(width: 90, alignment: .leading)
            picker().labelsHidden().pickerStyle(.menu).tint(Palette.accent).frame(maxWidth: 300)
            Spacer()
        }
    }

    private func symbol(for action: String) -> String {
        switch action {
        case "shutdown": "power"
        case "reboot": "arrow.triangle.2.circlepath"
        case "restart", "restart_safe": "arrow.clockwise"
        default: "terminal"
        }
    }

    private func syncConnection() {
        guard let connection = session.connection else { return }
        port = connection.current.port ?? connection.options.portPreference ?? ""
        baudrate = connection.current.baudrate ?? connection.options.baudratePreference ?? 0
        profile = connection.current.printerProfile ?? connection.options.printerProfilePreference ?? ""
    }
}

/// Drag-and-drop payloads for moving files between folders. Tagged with the printer, so dropping on another
/// printer's file list does nothing.
enum FileDrag {
    static let prefix = "octomac-file:"

    static func payload(for file: FileEntry, instance: UUID) -> String { "\(prefix)\(instance.uuidString):\(file.path)" }

    /// The dragged file's path, if the drag came from this printer's file list.
    static func path(from payload: String, instance: UUID) -> String? {
        let tag = "\(prefix)\(instance.uuidString):"
        guard payload.hasPrefix(tag) else { return nil }
        let path = String(payload.dropFirst(tag.count))
        return path.isEmpty ? nil : path
    }
}

/// What follows the pointer while dragging a file.
struct FileDragPreview: View {
    let file: FileEntry
    let client: OctoPrintClient
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            FileThumbnail(file: file, client: client, tint: tint, radius: 8).frame(width: 36, height: 36)
            Text(file.isFolder ? file.displayName : SlicedName(file.displayName).title)
                .font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(1)
        }
        .padding(8)
        .padding(.trailing, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.extrusionHi))
    }
}

/// Highlights a folder while something is dragged over it, and moves the dropped item into it.
struct FolderDropTarget: ViewModifier {
    let enabled: Bool
    let folderPath: String
    let tint: Color
    var radius: CGFloat = 12
    let onDrop: (String) -> Bool
    @State private var targeted = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(targeted ? tint.opacity(0.18) : .clear))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(tint, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .opacity(targeted ? 1 : 0))
                .dropDestination(for: String.self) { items, _ in
                    guard let payload = items.first else { return false }
                    return onDrop(payload)
                } isTargeted: { targeted = $0 }
        } else {
            content
        }
    }
}

/// The first row inside a folder: goes back up a level (and accepts drops to move files up).
struct UpRow: View {
    let parentName: String
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.turn.up.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.dust)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.graphite))
                Text("Back to \(parentName)")
                    .font(Typeface.text(14, .demibold))
                    .foregroundStyle(hovering ? Palette.paper : Palette.dust)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Palette.extrusionHi : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// One of OctoPrint's console filters ("Suppress temperature messages" and so on), from its settings.
struct TerminalFilter: Identifiable {
    let name: String
    let regex: NSRegularExpression
    var id: String { name }

    /// "Suppress temperature messages" reads as "Temperature messages" under a "Hide" heading.
    var label: String {
        let trimmed = name.hasPrefix("Suppress ") ? String(name.dropFirst("Suppress ".count)) : name
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }

    func matches(_ line: String) -> Bool {
        regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    init?(name: String, pattern: String) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        self.name = name
        self.regex = regex
    }

    /// The filters configured in OctoPrint (`terminalFilters`), or OctoPrint's standard set if none are known yet.
    static func fromSettings(_ settings: JSONValue?) -> [TerminalFilter] {
        let configured = (settings?["terminalFilters"]?.arrayValue ?? []).compactMap { entry -> TerminalFilter? in
            guard let name = entry["name"]?.stringValue, let regex = entry["regex"]?.stringValue else { return nil }
            return cache(name: name, pattern: regex)
        }
        return configured.isEmpty ? standard : configured
    }

    static let standard: [TerminalFilter] = [
        ("Suppress temperature messages", #"(Send: (N\d+\s+)?M105)|(Recv:\s+(ok\s+([PBN]\d+\s+)*)?([BCLPR]|T\d*):-?\d+)"#),
        ("Suppress SD status messages", #"(Send: (N\d+\s+)?M27)|(Recv: SD printing byte)|(Recv: Not SD printing)"#),
        ("Suppress position messages", #"(Send:\s+(N\d+\s+)?M114)|(Recv:\s+(ok\s+)?X:[+-]?([0-9]*[.])?[0-9]+\s+Y:[+-]?([0-9]*[.])?[0-9]+\s+Z:[+-]?([0-9]*[.])?[0-9]+\s+E\d*:[+-]?([0-9]*[.])?[0-9]+).*"#),
        ("Suppress wait responses", #"Recv: wait"#),
        ("Suppress processing responses", #"Recv: (echo:\s*)?busy:\s*processing"#),
    ].compactMap { TerminalFilter(name: $0.0, pattern: $0.1) }

    /// OctoMac's own extra: the Prusa MMU's constant status chatter.
    static let mmu = TerminalFilter(name: "Suppress MMU chatter", pattern: #"Recv: echo:MMU2?:"#)!

    @MainActor private static var compiled: [String: TerminalFilter] = [:]

    private static func cache(name: String, pattern: String) -> TerminalFilter? {
        MainActor.assumeIsolated {
            let key = name + "\u{0}" + pattern
            if let hit = compiled[key] { return hit }
            let filter = TerminalFilter(name: name, pattern: pattern)
            compiled[key] = filter
            return filter
        }
    }
}

/// The switches behind the Console's "Hide messages" button.
struct TerminalFilterList: View {
    let filters: [TerminalFilter]
    let enabled: Set<String>
    let toggle: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hide these messages").font(Typeface.caption).foregroundStyle(Palette.faint)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            ForEach(filters) { filter in
                Toggle(isOn: Binding(get: { enabled.contains(filter.name) }, set: { toggle(filter.name, $0) })) {
                    Text(filter.label).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Palette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .padding(10)
        .frame(width: 290)
        .background(Palette.extrusion)
        .presentationBackground(Palette.extrusion)
    }
}

/// Words and phrases to pick out in the console, each with its own colour.
struct ConsoleHighlightEditor: View {
    let terms: [String]
    @Binding var replies: Bool
    let save: ([String]) -> Void
    @State private var draft = ""

    static let colors: [Color] = [Palette.warm, Palette.cold, Color(hex: 0xC792EA), Palette.hot, Color(hex: 0xF29E4C)]
    static func color(at index: Int) -> Color { colors[index % colors.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $replies) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Replies to my commands").font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                    Text("Tints what you send from here and the printer's answer.").font(Typeface.caption).foregroundStyle(Palette.faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Palette.accent)

            Divider().overlay(Palette.edge)

            Text("Highlight lines containing").font(Typeface.caption).foregroundStyle(Palette.faint)
            HStack(spacing: 8) {
                TextField("A word or phrase, e.g. FR:", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Palette.paper)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.graphite))
                    .onSubmit(add)
                    .overlay(alignment: .trailing) { ClearFieldButton(text: $draft).padding(.trailing, 8) }
                Button("Add", action: add)
                    .buttonStyle(.plate)
                    .controlSize(.small)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(Array(terms.enumerated()), id: \.element) { index, term in
                HStack(spacing: 8) {
                    Circle().fill(Self.color(at: index)).frame(width: 9, height: 9)
                    Text(term).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.paper).lineLimit(1)
                    Spacer()
                    Button { save(terms.filter { $0 != term }) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.faint)
                        .help("Stop highlighting \(term)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Self.color(at: index).opacity(0.12)))
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Palette.extrusion)
        .presentationBackground(Palette.extrusion)
    }

    private func add() {
        let term = draft.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !terms.contains(term) else { draft = ""; return }
        save(terms + [term])
        draft = ""
    }
}
