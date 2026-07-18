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
    @State private var feed = 100.0
    @State private var flow = 100.0

    private let steps: [Double] = [0.1, 1, 10, 50, 100]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !session.canControl {
                StageNotice(text: session.flags.isJobActive
                    ? "Moving the print head is locked while a print is running. Fan and speed still work."
                    : "Connect the printer to move it.")
            }

            HStack(alignment: .top, spacing: 20) {
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
                            dialRow("Print speed", value: $feed, range: 50...200, step: 5, unit: "%") { session.setFeedRate(Int(feed)) }
                            dialRow("Flow", value: $flow, range: 75...125, step: 1, unit: "%") { session.setFlowRate(Int(flow)) }
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
                .frame(width: 440)
            }
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
    let session: PrinterSession
    let filament: Color
    @State private var folder: [String] = []
    @State private var search = ""
    @State private var importing = false
    @State private var dropTargeted = false
    @State private var newFolder = ""
    @State private var creatingFolder = false
    @State private var pendingDelete: FileEntry?
    @State private var selectedFile: FileEntry.ID?

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
                .frame(width: 260)
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
                        ForEach(rows) { file in
                            FileRow(file: file, client: session.client, filament: filament, showPath: !search.isEmpty, canPrint: session.canControl,
                                    selected: selectedFile == file.id,
                                    select: { selectedFile = file.id },
                                    open: { folder.append(file.name) },
                                    openFile: { session.select(file, print: false) },
                                    delete: { pendingDelete = file })
                        }
                    }
                    .padding(8)
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
        .alert("New folder", isPresented: $creatingFolder) {
            TextField("Name", text: $newFolder)
            Button("Create") { session.createFolder(newFolder, in: folderPath); newFolder = "" }
            Button("Cancel", role: .cancel) { newFolder = "" }
        }
        .confirmationDialog("Delete “\(pendingDelete?.displayName ?? "")”?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let file = pendingDelete { session.delete(file) }
                pendingDelete = nil
            }
        } message: {
            Text(pendingDelete?.isFolder == true ? "The folder and everything in it will be deleted from the printer." : "The file will be deleted from the printer.")
        }
    }

    private var breadcrumbs: some View {
        HStack(spacing: 6) {
            crumb("All files", depth: 0)
            ForEach(Array(folder.enumerated()), id: \.offset) { index, name in
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.faint)
                crumb(name, depth: index + 1)
            }
        }
    }

    private func crumb(_ title: String, depth: Int) -> some View {
        Button { folder = Array(folder.prefix(depth)); search = "" } label: {
            Text(title)
                .font(Typeface.text(17, .demibold))
                .foregroundStyle(depth == folder.count ? Palette.paper : Palette.dust)
        }
        .buttonStyle(.plain)
    }

    private func flatten(_ files: [FileEntry]) -> [FileEntry] {
        files.flatMap { [$0] + flatten($0.children ?? []) }
    }

    static let uploadTypes: [UTType] = ["gcode", "gco", "g", "bgcode", "stl", "3mf"].compactMap { UTType(filenameExtension: $0) } + [.data]
}

private enum FileColumns {
    static let time: CGFloat = 100
    static let filament: CGFloat = 90
    static let size: CGFloat = 90
    static let actions: CGFloat = 230
}

/// Folders first, then files, each in Finder-style alphabetical order ("part 2" before "part 10").
func alphabetical(_ entries: [FileEntry]) -> [FileEntry] {
    entries.sorted { lhs, rhs in
        if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
}

struct FileHeaderRow: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 60)
            Text("Print time").frame(width: FileColumns.time, alignment: .trailing)
            Text("Filament").frame(width: FileColumns.filament, alignment: .trailing)
            Text("Size").frame(width: FileColumns.size, alignment: .trailing)
            Color.clear.frame(width: FileColumns.actions, height: 1)
        }
        .font(Typeface.caption)
        .foregroundStyle(Palette.faint)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

struct FileRow: View {
    let file: FileEntry
    let client: OctoPrintClient
    let filament: Color
    let showPath: Bool
    let canPrint: Bool
    let selected: Bool
    let select: () -> Void
    let open: () -> Void
    let openFile: () -> Void
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
                        if !file.isFolder, let date = file.date {
                            Text("added \(date.formatted(.relative(presentation: .named)))")
                                .font(Typeface.caption)
                                .foregroundStyle(Palette.faint)
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
            number(file.isFolder ? "" : Fmt.filament(file.gcodeAnalysis?.totalFilamentLength), width: FileColumns.filament)
            number(file.isFolder ? "\(file.children?.count ?? 0) items" : file.size.map(Fmt.bytes) ?? "", width: FileColumns.size)

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
            .frame(width: FileColumns.actions, alignment: .trailing)
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
                if file.isMachineCode { Button("Open", action: openFile).disabled(!canPrint) }
            }
            Divider()
            Button("Delete…", role: .destructive, action: delete)
        }
        .onTapGesture(count: 2) { if file.isFolder { open() } else if canPrint { openFile() } }
        .onTapGesture { file.isFolder ? open() : select() }
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
                    FilePreview(file: file, client: client, filament: filament, canOpen: canPrint) {
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
    @AppStorage("terminal.hideTemperature") private var hideTemperature = true
    @AppStorage("terminal.hideSD") private var hideSDStatus = true
    @State private var command = ""
    @State private var history: [String] = []
    @State private var historyIndex: Int?

    private static let temperaturePattern = /(Send:\s+(N\d+\s+)?M105)|(Recv:\s+(ok\s+)?(B|T\d*):)/
    private static let sdPattern = /(Send:\s+(N\d+\s+)?M27)|(Recv:\s+(SD printing byte|Not SD printing))/

    private var lines: [(offset: Int, element: String)] {
        Array(session.terminal.enumerated()).filter { _, line in
            !(hideTemperature && line.contains(Self.temperaturePattern)) && !(hideSDStatus && line.contains(Self.sdPattern))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Printer conversation").font(Typeface.subhead).foregroundStyle(Palette.paper)
                Spacer()
                Chip(title: "Hide temperature polling", selected: hideTemperature) { hideTemperature.toggle() }
                Chip(title: "Hide SD polling", selected: hideSDStatus) { hideSDStatus.toggle() }
            }
            .padding(20)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(lines, id: \.offset) { _, line in
                            ConsoleLine(line: line)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 20)
                    .textSelection(.enabled)
                }
                .background(Palette.graphite)
                .onChange(of: session.terminal.count) { proxy.scrollTo("end", anchor: .bottom) }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            }

            HStack(spacing: 10) {
                Text("›").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(Palette.accent)
                TextField("Send a G-code command, e.g. M115", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Palette.paper)
                    .onSubmit(send)
                    .onKeyPress(.upArrow) { recall(-1) }
                    .onKeyPress(.downArrow) { recall(1) }
                Button("Send", action: send)
                    .buttonStyle(.plate)
                    .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty || !session.flags.operational)
            }
            .padding(16)
        }
        .machined(radius: 20)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func send() {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        session.sendGcode(trimmed.uppercased(with: Locale(identifier: "en_US_POSIX")))
        if history.last != trimmed { history.append(trimmed) }
        historyIndex = nil
        command = ""
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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(direction).foregroundStyle(directionColor).frame(width: 14)
            Text(content).foregroundStyle(contentColor)
        }
        .font(.system(size: 12.5, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
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
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                    printerPanel
                    connectionPanel
                }
                VStack(spacing: 20) {
                    serverPanel
                    powerPanel
                }
            }
        }
        .onAppear(perform: syncConnection)
        .onChange(of: session.connection) { syncConnection() }
        .confirmationDialog(pendingCommand?.name ?? "", isPresented: Binding(get: { pendingCommand != nil }, set: { if !$0 { pendingCommand = nil } }), presenting: pendingCommand) { command in
            Button(command.name, role: .destructive) { session.run(command) }
        } message: { command in
            Text(command.confirm ?? "")
        }
    }

    private var printerPanel: some View {
        StagePanel(title: "Printer", detail: session.currentProfile?.model) {
            if let profile = session.currentProfile {
                VStack(alignment: .leading, spacing: 18) {
                    Text(profile.name).font(Typeface.title).foregroundStyle(Palette.paper)
                    HStack(alignment: .top, spacing: 36) {
                        if let volume = profile.volume {
                            fact("Build volume", [volume.width, volume.depth, volume.height].map { Fmt.number($0) }.joined(separator: " × "), unit: "mm")
                        }
                        fact("Nozzle", Fmt.number(profile.extruder?.nozzleDiameter ?? 0.4), unit: "mm")
                        fact("Extruders", "\(profile.extruder?.count ?? 1)", unit: nil)
                        fact("Heated bed", profile.heatedBed == true ? "Yes" : "No", unit: nil)
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
                HStack(alignment: .top, spacing: 36) {
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
            Text(title).font(Typeface.caption).foregroundStyle(Palette.faint)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(Typeface.number(24)).foregroundStyle(Palette.paper)
                if let unit { Text(unit).font(Typeface.number(13)).foregroundStyle(Palette.faint) }
            }
        }
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
