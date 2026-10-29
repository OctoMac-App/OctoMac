import OctoPrintKit
import SwiftUI

/// The Machine tab's plugin list: switch plugins on or off, update or uninstall them. Built-in plugins are hidden
/// unless you ask, since most of them can't be changed.
struct PluginsPanel: View {
    let session: PrinterSession
    let plugins: [InstalledPlugin]
    @State private var showBuiltIn = false
    @State private var uninstalling: InstalledPlugin?
    @State private var updating: [String]?
    @State private var restarting = false

    private var shown: [InstalledPlugin] { plugins.filter { showBuiltIn || !$0.bundled } }
    private var updatable: [String: SoftwareComponent] {
        Dictionary((session.updates ?? []).filter(\.updateAvailable).map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let added = plugins.filter { !$0.bundled }.count
        StagePanel(title: "Plugins", detail: "\(added) added, \(plugins.count - added) built in") {
            VStack(alignment: .leading, spacing: 12) {
                if session.updatingSince != nil {
                    notice("Updating. OctoPrint restarts when it's done, which can take a few minutes.", symbol: "arrow.triangle.2.circlepath", busy: true)
                } else if session.pluginsNeedRestart {
                    HStack(spacing: 10) {
                        notice("Restart OctoPrint to finish the changes.", symbol: "arrow.clockwise.circle.fill", busy: false)
                        Spacer()
                        if session.restartCommand != nil {
                            Button("Restart OctoPrint…") { restarting = true }
                                .buttonStyle(.plate(Palette.warm))
                                .controlSize(.small)
                                .disabled(session.flags.isJobActive)
                                .help(session.flags.isJobActive ? "Wait until the print finishes" : "Restart OctoPrint now")
                        }
                    }
                }

                if shown.isEmpty {
                    Text(showBuiltIn ? "No plugins." : "No plugins added yet. Find them in OctoPrint's Plugin Manager.")
                        .font(Typeface.body).foregroundStyle(Palette.dust)
                } else {
                    VStack(spacing: 0) {
                        ForEach(shown) { plugin in
                            PluginRow(session: session, plugin: plugin, update: updatable[plugin.key.lowercased()],
                                      uninstall: { uninstalling = plugin }, updateNow: { updating = [plugin.key] })
                            if plugin.id != shown.last?.id { Divider().overlay(Palette.edge) }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button(showBuiltIn ? "Hide built-in plugins" : "Show built-in plugins") {
                        withAnimation(.snappy) { showBuiltIn.toggle() }
                    }
                    .buttonStyle(.plateQuiet)
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(URL(string: "#settings_plugin_pluginmanager", relativeTo: session.instance.baseURL)?.absoluteURL
                                                ?? session.instance.baseURL)
                    } label: {
                        Label("Find more plugins", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.plateQuiet)
                    .help("Opens OctoPrint's Plugin Manager, where you can browse and install plugins")
                }
                .controlSize(.small)
            }
        }
        .sheet(item: $uninstalling) { plugin in
            ConfirmSheet(symbol: "trash", title: "Uninstall \(plugin.name)?",
                         message: "OctoPrint removes the plugin. Its settings may be kept in case you install it again. OctoPrint needs a restart afterwards.",
                         confirmTitle: "Uninstall", onConfirm: { session.uninstallPlugin(plugin) })
        }
        .sheet(isPresented: Binding(get: { updating != nil }, set: { if !$0 { updating = nil } })) {
            ConfirmSheet(symbol: "arrow.down.circle", tint: Palette.warm, title: "Update now?",
                         message: "OctoPrint downloads the update, installs it and restarts. The printer stays connected, but OctoMac loses touch with it for a minute or two.",
                         confirmTitle: "Update", onConfirm: { session.updateSoftware(updating ?? []) })
        }
        .sheet(isPresented: $restarting) {
            if let command = session.restartCommand {
                ConfirmSheet(symbol: "arrow.clockwise", tint: Palette.warm, title: "Restart OctoPrint?",
                             message: "OctoMac loses touch with the printer for a minute while OctoPrint starts again.",
                             confirmTitle: "Restart", onConfirm: { session.run(command) })
            }
        }
    }

    private func notice(_ text: String, symbol: String, busy: Bool) -> some View {
        HStack(spacing: 8) {
            if busy {
                ProgressView().controlSize(.small).tint(Palette.warm)
            } else {
                Image(systemName: symbol).foregroundStyle(Palette.warm)
            }
            Text(text).font(Typeface.bodyStrong).foregroundStyle(Palette.paper).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PluginRow: View {
    let session: PrinterSession
    let plugin: InstalledPlugin
    let update: SoftwareComponent?
    let uninstall: () -> Void
    let updateNow: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(plugin.name).font(Typeface.bodyStrong)
                        .foregroundStyle(plugin.enabled ? Palette.paper : Palette.dust)
                        .lineLimit(1)
                    if let version = plugin.version {
                        Text(version).font(Typeface.number(12)).foregroundStyle(Palette.faint).lineLimit(1)
                    }
                    if plugin.pending {
                        Text("After restart").font(Typeface.caption).foregroundStyle(Palette.warm)
                    } else if plugin.safeModeVictim {
                        Text("Off in safe mode").font(Typeface.caption).foregroundStyle(Palette.warm)
                    }
                }
                if let summary = plugin.summary, !summary.isEmpty {
                    Text(summary).font(Typeface.caption).foregroundStyle(Palette.faint).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let update, let available = update.available {
                Button("Update to \(available)", action: updateNow)
                    .buttonStyle(.plate(Palette.warm))
                    .controlSize(.small)
                    .disabled(session.flags.isJobActive || session.updatingSince != nil || !update.updatePossible)
                    .help(session.flags.isJobActive ? "Wait until the print finishes" : "Install the update; OctoPrint restarts afterwards")
            }
            AppMenu(items: menuItems, width: 220) {
                QuietMenuLabel(symbol: "ellipsis")
            }
            .disabled(plugin.homepage == nil && (plugin.bundled || !plugin.managable))
            Toggle("", isOn: Binding(get: { plugin.enabled }, set: { _ in session.togglePlugin(plugin) }))
                .toggleStyle(.switch)
                .tint(Palette.accent)
                .labelsHidden()
                .controlSize(.small)
                .disabled(!plugin.managable || plugin.pending)
                .help(plugin.managable ? (plugin.enabled ? "Switch off" : "Switch on") : "OctoPrint needs this plugin")
        }
        .padding(.vertical, 9)
    }

    private var menuItems: [AppMenuItem] {
        var items: [AppMenuItem] = []
        if let homepage = plugin.homepage {
            items.append(.action("Open plugin website", symbol: "safari") { NSWorkspace.shared.open(homepage) })
        }
        if !plugin.bundled && plugin.managable {
            items.append(.action("Uninstall…", symbol: "trash", destructive: true, run: uninstall))
        }
        return items
    }
}
