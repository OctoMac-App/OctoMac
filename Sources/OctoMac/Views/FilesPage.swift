import OctoPrintKit
import SwiftUI
import UniformTypeIdentifiers

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
    /// The next upload goes to the printer's SD card rather than the Raspberry Pi.
    @State private var importingToSD = false
    @State private var dropTargeted = false
    @State private var creatingFolder = false
    @State private var pendingDelete: FileEntry?
    @State private var sending: FileEntry?
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
            if !session.journal.queue.isEmpty {
                QueuePanel(session: session, filament: filament)
            }
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
                Button { importingToSD = false; importing = true } label: { Label("Upload", systemImage: "arrow.up") }
                    .buttonStyle(.plate)
            }

            VStack(spacing: 0) {
                FileHeaderRow()
                Divider().overlay(Palette.edge)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if !folder.isEmpty && search.isEmpty {
                            UpRow(parentName: folder.count > 1 ? folder[folder.count - 2] : String(localized: "All files"), tint: filament) { goUp() }
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
                                    send: { sending = file },
                                    queue: { session.addToQueue(file) },
                                    queued: session.journal.queue.contains { $0.path == file.path },
                                    duplicate: file.origin == .local && !file.isFolder ? { session.duplicate(file) } : nil,
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
                    Button("Upload files…") { importingToSD = false; importing = true }
                    if session.flags.sdReady {
                        Divider()
                        Button("Upload to the SD card…") {
                            importingToSD = true
                            importing = true
                        }
                        .disabled(session.flags.isJobActive)
                        Button("Refresh the SD card") { session.refreshSDCard() }
                            .disabled(session.flags.isJobActive)
                    }
                    if !folder.isEmpty {
                        Divider()
                        Button("Back to \(folder.count > 1 ? folder[folder.count - 2] : String(localized: "All files"))") { goUp() }
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
                        .overlay(Label("Drop to upload to \(folder.last ?? String(localized: "All files"))", systemImage: "arrow.up.doc")
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
            if case .success(let urls) = result { session.upload(urls, folder: folderPath, toSDCard: importingToSD) }
            importingToSD = false
        }
        .sheet(isPresented: $creatingFolder) {
            NameSheet(title: "New folder", placeholder: "Folder name", confirmTitle: "Create folder") { name in
                session.createFolder(name, in: folderPath)
            }
        }
        .sheet(item: $sending) { file in
            SendToPrinterSheet(source: session, file: file, filament: filament)
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
            crumb(String(localized: "All files"), depth: 0)
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
    static let actions: CGFloat = 312
    static let compactActions: CGFloat = 252
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
    let send: () -> Void
    let queue: () -> Void
    var queued = false
    /// Nil where a copy can't be made (folders, and files on the SD card).
    var duplicate: (() -> Void)?
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

            number(file.isFolder ? "" : Fmt.duration(file.expectedPrintTime?.seconds), width: FileColumns.time)
            if !compact {
                number(file.isFolder ? "" : Fmt.filament(file.gcodeAnalysis?.totalFilamentLength), width: FileColumns.filament)
                number(file.isFolder ? String(localized: "\(file.children?.count ?? 0) items") : file.size.map(Fmt.bytes) ?? "", width: FileColumns.size)
            }

            HStack(spacing: 8) {
                if hovering || selected {
                    if !file.isFolder {
                        Button(action: showInfo) { Image(systemName: "info.circle") }
                            .buttonStyle(.plateQuiet)
                            .help("Show file info")
                    }
                    if file.isMachineCode {
                        Button(action: queue) { Image(systemName: queued ? "text.badge.checkmark" : "text.badge.plus") }
                            .buttonStyle(.plateQuiet)
                            .help(queued ? "In the queue; add it again to print another" : "Add to the queue")
                        Button(action: send) { Image(systemName: "paperplane") }
                            .buttonStyle(.plateQuiet)
                            .help("Send to another printer")
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
                    Button("Add to Queue", action: queue)
                    Button("Send to Another Printer…", action: send)
                }
                if let duplicate { Button("Duplicate", action: duplicate) }
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
