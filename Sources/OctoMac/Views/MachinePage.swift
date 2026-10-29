import OctoPrintKit
import SwiftUI

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
                                if let plugins = session.plugins { PluginsPanel(session: session, plugins: plugins) }
                                if let backups = session.backups { BackupsPanel(session: session, state: backups) }
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
                        if let plugins = session.plugins { PluginsPanel(session: session, plugins: plugins) }
                        if let backups = session.backups { BackupsPanel(session: session, state: backups) }
                        LogsPanel(session: session)
                    }
                }
            }
        }
        // Loads again whenever the printer comes online: opened before OctoMac had connected (just after launch,
        // or while it was reconnecting), the first try finds nothing. A few quick retries cover a slow Pi.
        .task(id: "\(session.instance.id)-\(session.link == .online)") {
            guard session.link == .online else { return }
            for attempt in 0..<3 {
                if attempt > 0 {
                    try? await Task.sleep(for: .seconds(3))
                    if Task.isCancelled { return }
                }
                async let updates: Void = session.refreshUpdates()
                async let logs: Void = session.refreshLogs()
                async let health: Void = session.refreshHealth()
                async let plugins: Void = session.refreshPlugins()
                async let backups: Void = session.refreshBackups()
                _ = await (updates, logs, health, plugins, backups)
                if session.plugins != nil && !session.logs.isEmpty { return }
            }
        }
        .onAppear(perform: syncConnection)
        .onChange(of: session.connection) { syncConnection() }
        .sheet(item: $pendingCommand) { command in
            let name = OctoPrintWords.commandName(command)
            let message = [OctoPrintWords.commandConfirmation(command), String(localized: "Any print in progress will stop.")]
                .compactMap { $0 }.joined(separator: " ")
            ConfirmSheet(symbol: symbol(for: command.action), tint: Palette.warm, title: Text(verbatim: "\(name)?"),
                         message: Text(verbatim: message), confirmTitle: Text(verbatim: name), onConfirm: { session.run(command) })
        }
    }

    private var printerPanel: some View {
        StagePanel(title: "Printer", verbatimDetail: session.currentProfile?.model) {
            if let profile = session.currentProfile {
                VStack(alignment: .leading, spacing: 18) {
                    Text(verbatim: profile.name).font(Typeface.title).foregroundStyle(Palette.paper)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .topLeading)], alignment: .leading, spacing: 16) {
                        if let volume = profile.volume {
                            fact("Build volume", [volume.width, volume.depth, volume.height].map { Fmt.number($0) }.joined(separator: " × "), unit: "mm")
                        }
                        fact("Nozzle", Fmt.number(profile.extruder?.nozzleDiameter ?? 0.4), unit: "mm")
                        fact("Extruders", "\(profile.extruder?.count ?? 1)", unit: nil)
                        fact("Heated bed", profile.heatedBed == true ? String(localized: "Yes") : String(localized: "No"), unit: nil)
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
        StagePanel(title: "Serial connection", verbatimDetail: session.connection.map { OctoPrintWords.state($0.current.state) }) {
            if let options = session.connection?.options {
                VStack(spacing: 12) {
                    pickerRow("Port") {
                        PlateMenu(selection: $port, options: [("", String(localized: "Auto"))] + options.ports.map { ($0, $0) })
                    }
                    pickerRow("Baud rate") {
                        PlateMenu(selection: $baudrate, options: [(0, String(localized: "Auto"))] + options.baudrates.map { ($0, String($0)) })
                    }
                    pickerRow("Profile") {
                        PlateMenu(selection: $profile, options: [("", String(localized: "Default"))] + options.printerProfiles.map { ($0.id, $0.name) })
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
                        Text(verbatim: OctoPrintWords.commandName(command)).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                        Spacer()
                        if session.restartingSince != nil && command.source == "core" && command.action == "restart" {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small).tint(Palette.accent)
                                Text("Restarting…").font(Typeface.caption).foregroundStyle(Palette.dust)
                            }
                        } else {
                            Button("Run") {
                                if command.confirm != nil { pendingCommand = command } else { session.run(command) }
                            }
                            .buttonStyle(.plateQuiet)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .machined(radius: 12, fill: Palette.graphite)
                }
            }
        }
    }

    private func fact(_ title: LocalizedStringKey, _ value: String, unit: String?) -> some View {
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

    private func pickerRow<P: View>(_ title: LocalizedStringKey, @ViewBuilder picker: () -> P) -> some View {
        HStack {
            Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.dust).frame(width: 90, alignment: .leading)
            picker().frame(maxWidth: 300)
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
