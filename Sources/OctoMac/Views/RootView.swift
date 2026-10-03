import OctoPrintKit
import SwiftUI

enum EditorTarget: Identifiable {
    case new
    case edit(Instance)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let instance): instance.id.uuidString
        }
    }
}

enum StageTab: String, CaseIterable, Identifiable {
    case overview, move, files, history, console, machine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .move: "Move"
        case .files: "Files"
        case .history: "History"
        case .console: "Console"
        case .machine: "Machine"
        }
    }
}

struct RootView: View {
    @Environment(InstanceStore.self) private var store
    @AppStorage("selectedInstance") private var selectionStorage = ""
    /// Changing the temperature unit redraws everything that shows a temperature.
    @AppStorage(TemperatureUnit.defaultsKey) private var unit = TemperatureUnit.celsius.rawValue
    @State private var selection: UUID?
    @State private var editor: EditorTarget?
    @State private var inbox = FileInbox.shared
    @State private var choosingPrinter = false

    var body: some View {
        GeometryReader { geo in
        HStack(spacing: 0) {
            PrinterRail(selection: $selection, editor: $editor)
                .frame(width: geo.size.width < 1200 ? 216 : 260)
                .id(unit)

            ZStack {
                LayerLineBackground()
                if selection == AllPrinters.id, !store.instances.isEmpty {
                    AllPrintersStage(selection: $selection).id(unit)
                } else if let session = store.session(for: selection) {
                    PrinterStage(session: session, editor: $editor)
                        .id("\(ObjectIdentifier(session).hashValue)-\(unit)")
                } else {
                    EmptyStage(firstRun: store.instances.isEmpty) { editor = .new }
                }
            }
        }
        }
        .ignoresSafeArea()
        // The Prusa MMU plugin is waiting for a filament choice on some printer: ask, whichever printer is on screen.
        .overlay {
            if let session = store.instances.compactMap({ store.sessions[$0.id] }).first(where: { $0.mmuPromptSince != nil }),
               let since = session.mmuPromptSince, let settings = session.mmu {
                MMUPromptOverlay(session: session, settings: settings, since: since)
                    .id(since)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.instances.compactMap { store.sessions[$0.id]?.mmuPromptSince })
        .onChange(of: inbox.pending) { _, files in routeOpenedFiles(files) }
        .onAppear { routeOpenedFiles(inbox.pending) }
        .onAppear { WidgetFeed.shared.start(store: store) }
        .sheet(isPresented: $choosingPrinter, onDismiss: { inbox.pending = [] }) {
            UploadChooser(files: inbox.pending) { upload(inbox.pending, to: $0) }
        }
        .sheet(item: $editor) { target in
            InstanceEditor(target: target) { selection = $0 }
        }
        .onAppear {
            selection = UUID(uuidString: selectionStorage).flatMap { id in
                id == AllPrinters.id || store.instances.contains { $0.id == id } ? id : nil
            }
                ?? store.instances.first?.id
            // Demo screenshots: `--demo --select 2` picks the second printer.
            if store.isDemo, let flag = CommandLine.arguments.firstIndex(of: "--select"),
               CommandLine.arguments.indices.contains(flag + 1), let index = Int(CommandLine.arguments[flag + 1]),
               store.instances.indices.contains(index - 1) {
                selection = store.instances[index - 1].id
            }
        }
        // Demo printers aren't remembered as the selection, so leaving demo mode returns to your own printer.
        .onChange(of: selection) { _, new in if !store.isDemo { selectionStorage = new?.uuidString ?? "" } }
        // The menu bar panel selects a printer by writing the stored selection.
        .onChange(of: selectionStorage) { _, new in
            if let id = UUID(uuidString: new), id != selection { selection = id }
        }
        .onChange(of: store.isDemo) { _, demo in
            selection = demo
                ? store.instances.first?.id
                : UUID(uuidString: selectionStorage).flatMap { id in store.instances.contains { $0.id == id } ? id : nil }
                    ?? store.instances.first?.id
        }
    }

    /// Files opened from Finder go straight to the only reachable printer, or you choose.
    private func routeOpenedFiles(_ files: [URL]) {
        guard !files.isEmpty, !choosingPrinter else { return }
        let online = store.instances.filter { store.sessions[$0.id]?.link == .online }
        if online.count == 1, store.instances.count == 1 {
            upload(files, to: online[0].id)
        } else {
            choosingPrinter = true
        }
    }

    private func upload(_ files: [URL], to id: UUID) {
        selection = id
        store.sessions[id]?.upload(files)
        inbox.pending = []
    }
}

// MARK: - Rail

struct PrinterRail: View {
    @Environment(InstanceStore.self) private var store
    @Binding var selection: UUID?
    @Binding var editor: EditorTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the window's traffic lights.
            Color.clear.frame(height: 52)

            Text("Printers")
                .font(Typeface.caption)
                .foregroundStyle(Palette.faint)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 8) {
                    if store.instances.count > 1 {
                        AllPrintersTile(selected: selection == AllPrinters.id) { selection = AllPrinters.id }
                    }
                    ForEach(store.instances) { instance in
                        if let session = store.sessions[instance.id] {
                            Button { selection = instance.id } label: {
                                PrinterTile(session: session, filament: store.filament(for: instance), selected: selection == instance.id)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(instance.name), \(session.stateText)")
                                .contextMenu {
                                    Button("Edit printer…") { editor = .edit(instance) }
                                    Divider()
                                    Button("Remove printer", role: .destructive) {
                                        if selection == instance.id { selection = nil }
                                        store.remove(instance.id)
                                    }
                                }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            Spacer(minLength: 0)

            Button { editor = .new } label: {
                Label("Add a printer", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plateQuiet)
            .padding(.horizontal, 16)

            // Centred under the Add a printer button. In demo mode the Exit demo badge sits beside
            // the logo when there's room, or underneath it in the narrow sidebar.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    BrandLockup(markSize: store.isDemo ? 32 : 40)
                    if store.isDemo { exitDemo }
                }
                VStack(spacing: 8) {
                    BrandLockup(markSize: 32)
                    if store.isDemo { exitDemo }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Palette.rail)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.black.opacity(0.35)).frame(width: 1) }
    }

    private var exitDemo: some View {
        Button { store.exitDemo() } label: {
            Text("Exit demo")
                .font(Typeface.text(11, .demibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Palette.graphite)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Palette.accent))
        }
        .buttonStyle(.plain)
        .help("Leave demo mode and reconnect to your printers")
    }
}

struct PrinterTile: View {
    let session: PrinterSession
    let filament: Color
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        let mood = PrinterMood(session)
        HStack(alignment: .top, spacing: 12) {
            // Filament strip: the printer's identity colour.
            Capsule()
                .fill(filament.opacity(selected ? 1 : 0.6))
                .frame(width: 4)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(session.instance.name)
                        .font(Typeface.text(15, .demibold))
                        .foregroundStyle(Palette.paper)
                        .lineLimit(1)
                    Spacer()
                    StatusLamp(color: mood.color(filament: filament), lit: mood != .offline)
                }

                Text(subtitle(mood))
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.dust)
                    .lineLimit(1)

                if mood == .printing || mood == .paused, let fraction = session.progress?.fraction {
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette.edge.opacity(0.5))
                                Capsule().fill(filament).frame(width: geo.size.width * fraction)
                            }
                        }
                        .frame(height: 4)
                        Text("\(Int(fraction * 100))%").font(Typeface.number(12)).foregroundStyle(Palette.paper)
                    }
                } else if let tool = session.heaters["tool0"]?.actual, mood != .offline, mood != .locked {
                    HStack(spacing: 10) {
                        temp(.tool(0), tool)
                        if let bed = session.heaters["bed"]?.actual { temp(.bed, bed) }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if selected || hovering {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Palette.extrusion : Palette.extrusion.opacity(0.5))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func subtitle(_ mood: PrinterMood) -> String {
        switch mood {
        case .printing, .paused:
            let left = session.progress?.printTimeLeft.map { "\(Fmt.duration($0)) left" }
            return [session.state?.text, left].compactMap { $0 }.joined(separator: ", ")
        default:
            return session.stateText
        }
    }

    private func temp(_ kind: HeaterKind, _ value: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: kind.symbol).font(.system(size: 9)).foregroundStyle(kind.color)
            Text(Fmt.deg(value)).font(Typeface.number(12)).foregroundStyle(Palette.dust)
        }
    }
}

struct EmptyStage: View {
    /// No printers added yet: greet rather than ask for a selection.
    var firstRun = false
    let add: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            BrandLockup(markSize: 72)
                .padding(.bottom, 8)
            Text(firstRun ? "Welcome to OctoMac" : "No printer selected")
                .font(Typeface.title).foregroundStyle(Palette.paper)
            Text(firstRun
                 ? "Add your first OctoPrint server to get started. You'll need its address, like octopi.local."
                 : "Pick a printer on the left, or add an OctoPrint server.")
                .font(Typeface.body).foregroundStyle(Palette.dust)
                .multilineTextAlignment(.center)
            Button(firstRun ? "Add your first printer" : "Add a printer", action: add).buttonStyle(.plate)
        }
        .frame(maxWidth: 420)
    }
}

/// The sidebar entry for the grid of every printer.
struct AllPrintersTile: View {
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Palette.accent : Palette.dust)
                    .frame(width: 18)
                Text("All printers").font(Typeface.text(14, .demibold)).foregroundStyle(Palette.paper)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if selected || hovering {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Palette.extrusionHi : Palette.extrusion)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
