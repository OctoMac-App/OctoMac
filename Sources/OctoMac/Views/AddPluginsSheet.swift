import OctoPrintKit
import SwiftUI

/// Browse OctoPrint's official plugin list and install from it. OctoPrint does the installing and sends its log
/// back as it goes. Installing from a web address or a file is left to OctoPrint's own Plugin Manager.
struct AddPluginsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    @State private var search = ""
    @State private var showHidden = false
    @State private var confirming: RepositoryPlugin?

    private var installed: Set<String> { Set((session.plugins ?? []).map { $0.key.lowercased() }) }

    /// Plugins that won't work here, or that nobody looks after any more.
    private func isHidden(_ plugin: RepositoryPlugin) -> Bool { !plugin.compatible || plugin.abandoned }

    private var matching: [RepositoryPlugin] {
        let all = session.pluginRepository ?? []
        let words = search.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return all }
        return all.filter { plugin in
            let text = [plugin.title, plugin.summary ?? "", plugin.author ?? "", plugin.id].joined(separator: " ")
            return words.allSatisfy { text.localizedCaseInsensitiveContains($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add plugins").font(Typeface.title).foregroundStyle(Palette.paper)
                Text("From OctoPrint's official plugin list. Plugins are made by the OctoPrint community, not by OctoMac.")
                    .font(Typeface.body).foregroundStyle(Palette.dust)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let install = session.pluginInstall {
                InstallProgress(session: session, install: install)
            } else {
                browser
            }

            buttons.controlSize(.small)
        }
        .padding(26)
        .frame(width: 640, height: 640)
        .background(Palette.extrusion)
        .interactiveDismissDisabled(session.pluginInstall?.isRunning == true && session.link == .online)
        .sheet(item: $confirming) { plugin in
            ConfirmSheet(symbol: "puzzlepiece.extension", tint: Palette.accent, title: "Install \(plugin.title)?",
                         message: "OctoPrint downloads it from its plugin list and installs it. Plugins are made by the OctoPrint community, not by OctoMac, and most need OctoPrint to restart afterwards.",
                         confirmTitle: "Install", onConfirm: { session.installPlugin(plugin) })
        }
        .task { await session.refreshPluginRepository() }
        .onDisappear { session.dismissPluginInstall() }
        .animation(.easeOut(duration: 0.2), value: session.pluginInstall == nil)
    }

    private var buttons: some View {
        let stage = session.pluginInstall.map { InstallStage(session: session, install: $0) }
        return HStack(spacing: 10) {
            if stage == nil {
                Button {
                    NSWorkspace.shared.open(URL(string: "#settings_plugin_pluginmanager", relativeTo: session.instance.baseURL)?.absoluteURL
                                            ?? session.instance.baseURL)
                } label: {
                    Label("Open OctoPrint's Plugin Manager", systemImage: "arrow.up.right")
                }
                .buttonStyle(.plateQuiet)
                .help("To install a plugin from a web address or a file")
            }
            Spacer()
            switch stage {
            case .needsRestart? where session.restartCommand != nil:
                // The next step is a restart, so that's the main button; the rest can wait.
                Button("Restart later") { dismiss() }.buttonStyle(.plateQuiet)
                Button { if let command = session.restartCommand { session.run(command) } } label: {
                    Label("Restart OctoPrint", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plate(Palette.warm))
                .keyboardShortcut(.defaultAction)
                .disabled(session.flags.isJobActive)
                .help(session.flags.isJobActive ? "Wait until the print finishes" : "Restart OctoPrint now")
            case .failed?, .installed?, .needsRestart?, .ready?:
                Button("Back to the list") { session.dismissPluginInstall() }.buttonStyle(.plateQuiet)
                done
            case .installing?:
                // Stay until OctoPrint says how it went, so a failure is never missed (unless OctoPrint has gone away).
                done
                    .disabled(session.link == .online)
                    .help("Wait for the install to finish")
            default:
                done
            }
        }
    }

    private var done: some View {
        Button("Done") { dismiss() }
            .buttonStyle(.plate)
            .keyboardShortcut(.defaultAction)
    }

    @ViewBuilder private var browser: some View {
        if let blocker = session.pluginInstallBlocker {
            Label(blocker, systemImage: "exclamationmark.triangle.fill")
                .font(Typeface.bodyStrong).foregroundStyle(Palette.warm)
                .fixedSize(horizontal: false, vertical: true)
        } else if session.flags.isJobActive {
            Label("You can install plugins once the print has finished.", systemImage: "clock")
                .font(Typeface.bodyStrong).foregroundStyle(Palette.warm)
        }

        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
            TextField("Search, for example \"timelapse\" or \"camera\"", text: $search)
                .textFieldStyle(.plain)
                .font(Typeface.body)
                .foregroundStyle(Palette.paper)
            ClearFieldButton(text: $search)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Palette.graphite))
        .overlay(Capsule().strokeBorder(Palette.edge, lineWidth: 1))

        Group {
            if let error = session.pluginRepositoryError {
                VStack(alignment: .leading, spacing: 10) {
                    Text("OctoPrint couldn't fetch the plugin list. Check the Raspberry Pi can reach the internet.")
                        .font(Typeface.body).foregroundStyle(Palette.dust)
                    Text(verbatim: error).font(Typeface.caption).foregroundStyle(Palette.faint).textSelection(.enabled)
                    Button("Try again") { Task { await session.refreshPluginRepository(force: true) } }
                        .buttonStyle(.plateQuiet).controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if session.pluginRepository == nil {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(Palette.accent)
                    Text("Fetching the plugin list…").font(Typeface.body).foregroundStyle(Palette.dust)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var list: some View {
        let matching = matching
        let shown = matching.filter { showHidden || !isHidden($0) }
        let hidden = matching.count - matching.filter { !isHidden($0) }.count
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if shown.isEmpty {
                    Text(search.isEmpty ? "The plugin list is empty." : "No plugins match your search.")
                        .font(Typeface.body).foregroundStyle(Palette.dust)
                        .padding(.vertical, 12)
                }
                ForEach(shown) { plugin in
                    RepositoryRow(session: session, plugin: plugin, installed: installed.contains(plugin.id.lowercased())) { confirming = plugin }
                    if plugin.id != shown.last?.id { Divider().overlay(Palette.edge) }
                }
                if hidden > 0 {
                    HStack(spacing: 10) {
                        Text(showHidden ? "Showing \(hidden) plugins that don't work with this OctoPrint or are no longer looked after."
                                        : "\(hidden) more are hidden because they don't work with this OctoPrint or are no longer looked after.")
                            .font(Typeface.caption).foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(showHidden ? "Hide them" : "Show them") { withAnimation(.snappy) { showHidden.toggle() } }
                            .buttonStyle(.plateQuiet).controlSize(.small)
                    }
                    .padding(.top, 14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.automatic)
        .machined(radius: 14, fill: Palette.graphite)
    }
}

private struct RepositoryRow: View {
    let session: PrinterSession
    let plugin: RepositoryPlugin
    let installed: Bool
    let install: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: plugin.title).font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(1)
                    if let author = plugin.author, !author.isEmpty {
                        Text("by \(author)").font(Typeface.caption).foregroundStyle(Palette.faint).lineLimit(1)
                    }
                }
                if let summary = plugin.summary, !summary.isEmpty {
                    Text(verbatim: summary).font(Typeface.caption).foregroundStyle(Palette.dust)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Group {
                    if !plugin.compatible {
                        Text("Doesn't work with this OctoPrint").foregroundStyle(Palette.warm)
                    } else if plugin.abandoned {
                        Text("No longer looked after").foregroundStyle(Palette.warm)
                    } else if plugin.users > 0 {
                        Text("Used on \(plugin.users) printers last month").foregroundStyle(Palette.faint)
                    }
                }
                .font(Typeface.caption)
            }
            Spacer(minLength: 8)
            if let page = plugin.page ?? plugin.homepage {
                Button { NSWorkspace.shared.open(page) } label: { QuietMenuLabel(symbol: "safari", chevron: false) }
                    .buttonStyle(.plain)
                    .help("Open the plugin's page")
            }
            if installed {
                Label("Installed", systemImage: "checkmark")
                    .font(Typeface.caption).foregroundStyle(Palette.ready)
                    .frame(height: 26)
            } else {
                Button("Install…", action: install)
                    .buttonStyle(.plate)
                    .controlSize(.small)
                    .disabled(!plugin.compatible || session.pluginInstallBlocker != nil || session.flags.isJobActive)
            }
        }
        .padding(.vertical, 10)
    }
}

/// Where an install has got to, including the restart many plugins need afterwards.
enum InstallStage: Equatable {
    case installing, failed(String), installed, needsRestart, restarting, ready

    @MainActor init(session: PrinterSession, install: PluginInstall) {
        switch install.outcome {
        case nil: self = .installing
        case .failed(let reason): self = .failed(reason)
        case .installed(needsRestart: false): self = .installed
        case .installed(needsRestart: true):
            self = install.restarted ? .ready : session.restartingSince != nil ? .restarting : .needsRestart
        }
    }
}

/// OctoPrint's install log as it arrives, then how it went, and the restart.
private struct InstallProgress: View {
    let session: PrinterSession
    let install: PluginInstall

    var body: some View {
        let stage = InstallStage(session: session, install: install)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    switch stage {
                    case .installing, .restarting: ProgressView().controlSize(.small).tint(Palette.accent)
                    case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(Palette.hot)
                    case .needsRestart: Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(Palette.warm)
                    case .installed, .ready: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.ready)
                    }
                }
                .font(.system(size: 20))
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(heading(stage)).font(Typeface.subhead).foregroundStyle(Palette.paper)
                    detail(stage)
                        .font(Typeface.body).foregroundStyle(Palette.dust)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .animation(.snappy, value: stage)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(install.log.enumerated()), id: \.offset) { index, line in
                            Text(verbatim: line)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Palette.dust)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: install.log.count) { _, count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
            .frame(maxHeight: .infinity)
            .machined(radius: 14, fill: Palette.graphite)
        }
    }

    private func heading(_ stage: InstallStage) -> String {
        let name = install.plugin.title
        return switch stage {
        case .installing: String(localized: "Installing \(name)…")
        case .failed: String(localized: "Couldn't install \(name)")
        case .installed, .needsRestart: String(localized: "Installed \(name)")
        case .restarting: String(localized: "Restarting OctoPrint…")
        case .ready: String(localized: "\(name) is ready")
        }
    }

    private func detail(_ stage: InstallStage) -> Text {
        switch stage {
        case .installing:
            Text("This can take a few minutes on a Raspberry Pi.")
        case .failed(let reason):
            Text(verbatim: reason)
        case .installed:
            Text("It's ready to use.")
        case .needsRestart:
            session.restartCommand == nil
                ? Text("Restart OctoPrint to start using it.")
                : Text("OctoPrint needs a restart to start using it. OctoMac loses touch with the printer for a minute while it starts again.")
        case .restarting:
            Text("\(install.plugin.title) starts once OctoPrint is back. This usually takes a minute.")
        case .ready:
            Text("OctoPrint has restarted and the plugin is running.")
        }
    }
}
