import OctoPrintKit
import SwiftUI

struct PrinterStage: View {
    @Environment(InstanceStore.self) private var store
    let session: PrinterSession
    @Binding var editor: EditorTarget?
    /// Each printer remembers its own tab, so you can keep one on Overview and another on Files.
    @AppStorage private var tab: StageTab

    init(session: PrinterSession, editor: Binding<EditorTarget?>) {
        self.session = session
        _editor = editor
        _tab = AppStorage(wrappedValue: .overview, "stageTab.\(session.instance.id.uuidString)")
    }
    @State private var confirmingStop = false
    @State private var confirmingEmergency = false

    var body: some View {
        let filament = store.filament(for: session.instance)
        VStack(alignment: .leading, spacing: 0) {
            StageHeader(session: session, filament: filament, tab: $tab, editor: $editor,
                        confirmingStop: $confirmingStop, confirmingEmergency: $confirmingEmergency)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 18)

            Group {
                if session.link == .needsAPIKey {
                    LockedStage(session: session, editor: $editor)
                } else {
                    switch tab {
                    case .overview: OverviewPage(session: session, filament: filament, tab: $tab)
                    case .move: MovePage(session: session)
                    case .files: FilesPage(session: session, filament: filament) { tab = .overview }
                    case .console: ConsolePage(session: session)
                    case .machine: MachinePage(session: session, filament: filament)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .bottomTrailing) {
            if !session.uploads.isEmpty {
                UploadPanel(session: session)
                    .padding(.trailing, 32)
                    .padding(.bottom, 36)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: session.uploads.isEmpty)
        .overlay(alignment: .bottom) {
            if let error = session.error {
                ErrorToast(message: error.message) { session.error = nil }
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: session.error)
        .overlay {
            if confirmingStop {
                StopPrintConfirmation(session: session, filament: filament, isPresented: $confirmingStop)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: confirmingStop)
        .overlay {
            if confirmingEmergency {
                EmergencyStopConfirmation(session: session, isPresented: $confirmingEmergency)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: confirmingEmergency)
        // Nothing to confirm once the job has ended some other way.
        .onChange(of: session.flags.isJobActive) { _, active in if !active { confirmingStop = false } }
    }
}

struct StageHeader: View {
    let session: PrinterSession
    let filament: Color
    @Binding var tab: StageTab
    @Binding var editor: EditorTarget?
    @Binding var confirmingStop: Bool
    @Binding var confirmingEmergency: Bool

    var body: some View {
        // Everything on one line when it fits. Narrower, the header uses two rows and then three,
        // so the buttons move out of the way instead of squashing the printer's name.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                title.fixedSize()
                Spacer(minLength: 12)
                if session.link != .needsAPIKey {
                    TabTrack(selection: $tab).fixedSize()
                    Spacer(minLength: 12)
                    actions
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    title.fixedSize()
                    Spacer(minLength: 12)
                    if session.link != .needsAPIKey { actions }
                }
                if session.link != .needsAPIKey {
                    TabTrack(selection: $tab).fixedSize()
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                title.fixedSize()
                if session.link != .needsAPIKey {
                    HStack(alignment: .center, spacing: 16) {
                        TabTrack(selection: $tab).fixedSize()
                        Spacer(minLength: 12)
                        actions
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                title.fixedSize(horizontal: false, vertical: true)
                if session.link != .needsAPIKey {
                    actions.frame(maxWidth: .infinity, alignment: .trailing)
                    TabTrack(selection: $tab).fixedSize()
                }
            }
        }
    }

    private var actions: some View {
        JobActions(session: session, confirmingStop: $confirmingStop, confirmingEmergency: $confirmingEmergency)
            .fixedSize()
    }

    private var title: some View {
        let mood = PrinterMood(session)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(session.instance.name)
                    .font(Typeface.display)
                    .foregroundStyle(Palette.paper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                HStack(spacing: 2) {
                    HeaderIconButton(symbol: "slider.horizontal.3", help: "Edit this printer") {
                        editor = .edit(session.instance)
                    }
                    OpenInBrowserButton(url: session.instance.baseURL)
                }
                .fixedSize()
            }
            HStack(spacing: 8) {
                StatusLamp(color: mood.color(filament: filament), lit: mood != .offline)
                Text(session.stateText).font(Typeface.bodyStrong).foregroundStyle(Palette.dust).lineLimit(1)
                if let profile = session.currentProfile?.name, session.link == .online {
                    // The first thing to give way when the window is narrow.
                    Text(profile).font(Typeface.body).foregroundStyle(Palette.faint).lineLimit(1)
                        .layoutPriority(-1)
                }
                if let mmu = session.mmu, let tool = session.mmuTool,
                   let filament = mmu.filaments.first(where: { $0.index == tool }) {
                    HStack(spacing: 5) {
                        Circle().fill(filament.color.flatMap(Color.init(hexString:)) ?? Palette.dust).frame(width: 9, height: 9)
                        Text(mmu.label(for: filament)).font(Typeface.body).foregroundStyle(Palette.dust).lineLimit(1)
                    }
                    .help("Loaded in the MMU: slot \(mmu.number(for: filament))")
                }
                if session.throttle?.currentIssue == true {
                    Label("Pi warning", systemImage: "exclamationmark.triangle.fill")
                        .font(Typeface.bodyStrong).foregroundStyle(Palette.warm).lineLimit(1)
                        .help("The Raspberry Pi is short of power or too hot. See the Machine tab.")
                }
            }
        }
    }
}

/// A small icon button beside the printer's name; quiet until hovered.
struct HeaderIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(hovering ? Palette.paper : Palette.faint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(hovering ? Palette.extrusionHi : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Opens the printer's OctoPrint web interface in the default browser.
struct OpenInBrowserButton: View {
    let url: URL
    @State private var hovering = false

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 5) {
                Text("Open OctoPrint").font(Typeface.text(12, .demibold))
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(hovering ? Palette.paper : Palette.dust)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(hovering ? Palette.extrusionHi : Palette.extrusion))
            .overlay(Capsule().strokeBorder(Palette.edge, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open \(url.host() ?? "OctoPrint") in your browser")
        .padding(.leading, 6)
    }
}

/// Text tabs on a machined track with a sliding bronze carriage.
struct TabTrack: View {
    @Binding var selection: StageTab
    @Namespace private var carriage

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StageTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = tab }
                } label: {
                    Text(tab.title)
                        .font(Typeface.text(13, .demibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selection == tab ? Palette.graphite : Palette.dust)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background {
                            if selection == tab {
                                Capsule().fill(Palette.accent).matchedGeometryEffect(id: "carriage", in: carriage)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character(String(StageTab.allCases.firstIndex(of: tab)! + 1))), modifiers: .command)
            }
        }
        .padding(4)
        .background(Capsule().fill(Palette.extrusion))
        .overlay(Capsule().strokeBorder(.white.opacity(0.05), lineWidth: 1))
    }
}

struct JobActions: View {
    let session: PrinterSession
    @Binding var confirmingStop: Bool
    @Binding var confirmingEmergency: Bool

    var body: some View {
        let flags = session.flags
        HStack(spacing: 10) {
            ConnectionButton(session: session)

            if flags.cancelling {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Palette.hot)
                    Text("Stopping…").font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .machined(radius: 17)
            } else if flags.printing || flags.pausing {
                Button { session.jobCommand(.pause) } label: { Label("Pause", systemImage: "pause.fill") }
                    .buttonStyle(.plate(Palette.warm))
            } else if flags.paused {
                Button { session.jobCommand(.resume) } label: { Label("Resume", systemImage: "play.fill") }
                    .buttonStyle(.plate)
            } else if session.job?.hasFile == true {
                Button { session.jobCommand(.start) } label: { Label("Print", systemImage: "play.fill") }
                    .buttonStyle(.plate)
                    .disabled(!(flags.operational && flags.ready))
            }

            if flags.isJobActive && !flags.cancelling {
                Button { confirmingStop = true } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.plateQuiet)
            }

            if session.isPrinterConnected {
                Button { confirmingEmergency = true } label: {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white, Palette.hot)
                        .frame(width: 36, height: 34)
                        .background(Circle().fill(Palette.hot.opacity(0.18)))
                        .overlay(Circle().strokeBorder(Palette.hot.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Emergency stop (M112): halts the printer immediately")
            }
        }
        .labelStyle(.titleAndIcon)
    }
}

/// Emergency stop: one deliberate click, with a plain description of the consequences.
struct EmergencyStopConfirmation: View {
    let session: PrinterSession
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "xmark.octagon.fill").font(.system(size: 30)).foregroundStyle(.white, Palette.hot)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Emergency stop").font(Typeface.title).foregroundStyle(Palette.paper)
                        Text("\(session.instance.name), M112").font(Typeface.number(13)).foregroundStyle(Palette.faint)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    bullet("bolt.slash.fill", "The printer halts immediately: heaters and motors switch off, even mid-move.")
                    bullet("stop.circle", "Any print is lost and can't be resumed.")
                    bullet("arrow.clockwise", "Afterwards, reset the printer (press the knob or power cycle) and reconnect it here.")
                }

                Text("To finish a print gracefully instead, use Stop, which lets OctoPrint run its cancel routine.")
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(.plateQuiet)
                        .keyboardShortcut(.cancelAction)
                    Button {
                        session.emergencyStop()
                        isPresented = false
                    } label: { Label("Emergency stop", systemImage: "xmark.octagon.fill") }
                        .buttonStyle(.plate(Palette.hot))
                }
            }
            .padding(28)
            .frame(width: 500)
            .machined(radius: 22, fill: Palette.extrusion)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.hot.opacity(0.45), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Palette.hot).frame(width: 18)
            Text(text).font(Typeface.body).foregroundStyle(Palette.dust).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Confirmation before cancelling a print: shows exactly what would be lost and offers pausing instead.
struct StopPrintConfirmation: View {
    let session: PrinterSession
    let filament: Color
    @Binding var isPresented: Bool

    var body: some View {
        let entry = session.fileEntry(for: session.job?.file)
        let name = SlicedName(session.job?.file.displayName ?? "")
        let fraction = session.progress?.fraction ?? 0
        let canPause = session.flags.printing && !session.flags.pausing

        ZStack {
            // Clicking outside keeps printing.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "stop.circle.fill").font(.system(size: 26)).foregroundStyle(Palette.hot)
                    Text("Stop this print?").font(Typeface.title).foregroundStyle(Palette.paper)
                }

                HStack(alignment: .top, spacing: 16) {
                    FileThumbnail(file: entry, client: session.client, tint: filament, radius: 12)
                        .frame(width: 88, height: 88)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(name.title).font(Typeface.subhead).foregroundStyle(Palette.paper).lineLimit(2)
                        if !name.tags.isEmpty { TagRow(tags: name.tags) }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette.edge.opacity(0.6))
                                Capsule().fill(filament).frame(width: max(4, geo.size.width * fraction))
                            }
                        }
                        .frame(height: 5)
                        Text(progressSummary)
                            .font(Typeface.number(13))
                            .foregroundStyle(Palette.dust)
                    }
                }
                .padding(14)
                .machined(radius: 14, fill: Palette.graphite)

                Text("A stopped print can't be resumed. The part stays on the bed as it is, and OctoPrint runs its cancel routine, which usually turns the heaters off and parks the print head.")
                    .font(Typeface.body)
                    .foregroundStyle(Palette.dust)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if canPause {
                        Button {
                            session.jobCommand(.pause)
                            isPresented = false
                        } label: { Label("Pause instead", systemImage: "pause.fill") }
                            .buttonStyle(.plateQuiet)
                    }
                    Spacer()
                    Button("Keep printing") { isPresented = false }
                        .buttonStyle(.plateQuiet)
                        .keyboardShortcut(.cancelAction)
                    Button {
                        session.stopPrint()
                        isPresented = false
                    } label: { Label("Stop print", systemImage: "stop.fill") }
                        .buttonStyle(.plate(Palette.hot))
                }
            }
            .padding(28)
            .frame(width: 520)
            .machined(radius: 22, fill: Palette.extrusion)
            .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
        }
    }

    private var progressSummary: String {
        let percent = Int((session.progress?.fraction ?? 0) * 100)
        var parts = ["\(percent)% done"]
        if let printTime = session.progress?.printTime, printTime > 0 { parts.append("printing for \(Fmt.duration(printTime))") }
        if let left = session.progress?.printTimeLeft, left > 0 { parts.append("\(Fmt.duration(left)) left") }
        return parts.joined(separator: ", ")
    }
}

struct ConnectionButton: View {
    let session: PrinterSession

    var body: some View {
        Menu {
            if session.isPrinterConnected {
                Button("Disconnect from printer") { session.disconnectPrinter() }
                    .disabled(session.flags.isJobActive)
            } else {
                Button("Connect automatically") { session.connectPrinter() }
                ForEach(session.connection?.options.ports ?? [], id: \.self) { port in
                    Button("Connect on \(port)") { session.connectPrinter(ConnectRequest(port: port)) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                StatusLamp(color: session.isPrinterConnected ? Palette.ready : Palette.faint, lit: session.isPrinterConnected)
                Text(session.isPrinterConnected ? (session.connection?.current.port.map { ($0 as NSString).lastPathComponent } ?? "Connected") : "Not connected")
                    .font(Typeface.text(13, .demibold))
                    .foregroundStyle(Palette.paper)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .machined(radius: 17)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(session.isPrinterConnected ? "Printer connected (\(session.connection?.current.port ?? "serial"))" : "Printer not connected")
        .disabled(session.link != .online)
    }
}

/// Uploads in progress, bottom right of the printer view.
struct UploadPanel: View {
    let session: PrinterSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "arrow.up.circle.fill").foregroundStyle(Palette.accent)
                Text(heading).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                Spacer()
            }
            ForEach(session.uploads) { item in
                UploadRow(item: item) { session.dismissUpload(item.id) }
            }
        }
        .padding(16)
        .frame(width: 360)
        .machined(radius: 16, fill: Palette.extrusionHi)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }

    private var heading: String {
        let active = session.uploads.filter { $0.state == .uploading }.count
        if active == 0 { return session.uploads.contains { if case .failed = $0.state { true } else { false } } ? "Upload problem" : "Uploaded" }
        return active == 1 ? "Uploading 1 file" : "Uploading \(active) files"
    }
}

struct UploadRow: View {
    let item: UploadItem
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(SlicedName(item.filename).title)
                    .font(Typeface.body).foregroundStyle(Palette.paper)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                switch item.state {
                case .uploading:
                    Text("\(Int((item.fraction * 100).rounded()))%").font(Typeface.number(13)).foregroundStyle(Palette.dust)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                case .failed:
                    Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.faint)
                        .help("Dismiss")
                }
            }
            switch item.state {
            case .failed(let reason):
                Text(reason).font(Typeface.caption).foregroundStyle(Palette.hot).lineLimit(2)
            default:
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.graphite)
                        Capsule().fill(Palette.accent).frame(width: max(4, geo.size.width * item.fraction))
                    }
                }
                .frame(height: 5)
                .animation(.linear(duration: 0.2), value: item.fraction)
                if let size = item.size, item.state == .uploading {
                    Text("\(Fmt.bytes(Int(Double(size) * item.fraction))) of \(Fmt.bytes(size))")
                        .font(Typeface.caption).foregroundStyle(Palette.faint)
                }
            }
        }
    }
}

struct ErrorToast: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.hot)
            Text(message).font(Typeface.body).foregroundStyle(Palette.paper).lineLimit(3)
            Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Palette.dust) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .machined(radius: 14, fill: Palette.extrusionHi)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .frame(maxWidth: 560)
    }
}

// MARK: - Locked (needs API key)

struct LockedStage: View {
    @Environment(InstanceStore.self) private var store
    let session: PrinterSession
    @Binding var editor: EditorTarget?
    @State private var requesting: Task<Void, Never>?
    @State private var message: String?

    var body: some View {
        ZStack {
            BuildPlateTexture()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "key.horizontal.fill").font(.system(size: 26)).foregroundStyle(Palette.accent)
                Text("Let OctoMac talk to \(session.instance.name)")
                    .font(Typeface.title)
                    .foregroundStyle(Palette.paper)
                Text("OctoMac needs permission from this OctoPrint server. Request access, then approve it in the OctoPrint page that opens in your browser. The key is saved on this Mac for your user account only.")
                    .font(Typeface.body)
                    .foregroundStyle(Palette.dust)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(session.instance.baseURL.absoluteString)
                    .font(Typeface.number(13))
                    .foregroundStyle(Palette.faint)

                if let message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(Typeface.body)
                        .foregroundStyle(Palette.hot)
                }

                HStack(spacing: 10) {
                    if requesting != nil {
                        ProgressView().controlSize(.small).tint(Palette.accent)
                        Text("Waiting for you to approve in OctoPrint…").font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                        Spacer()
                        Button("Stop waiting") { requesting?.cancel(); requesting = nil }.buttonStyle(.plateQuiet)
                    } else {
                        Button("Request access", action: request).buttonStyle(.plate)
                        Button("Paste a key instead") { editor = .edit(session.instance) }.buttonStyle(.plateQuiet)
                    }
                }
                .padding(.top, 6)
            }
            .padding(32)
            .frame(width: 520)
            .machined(radius: 20)
            .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        }
    }

    private func request() {
        let instance = session.instance
        message = nil
        requesting = Task {
            do {
                let key = try await AppKeysAuthorizer(baseURL: instance.baseURL).requestKey { url in
                    await MainActor.run { _ = NSWorkspace.shared.open(url) }
                }
                store.update(instance, apiKey: key)
            } catch is CancellationError {
            } catch {
                message = error.localizedDescription
            }
            requesting = nil
        }
    }
}
