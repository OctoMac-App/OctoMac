import AppKit
import SwiftUI
import UserNotifications

/// OctoMac → About OctoMac.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            BrandLockup(markSize: 64)
                .padding(.top, 8)
            Text("Version \(Diagnostics.appVersion)")
                .font(Typeface.number(14)).foregroundStyle(Palette.dust)
            Text("A friendly Mac app for your OctoPrint 3D printers.")
                .font(Typeface.body).foregroundStyle(Palette.paper)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/OctoMac-App/OctoMac")!)
                Link("Privacy", destination: URL(string: "https://github.com/OctoMac-App/OctoMac/blob/master/PRIVACY.md")!)
                Link("Licence", destination: URL(string: "https://github.com/OctoMac-App/OctoMac/blob/master/LICENSE")!)
            }
            .font(Typeface.bodyStrong)
            .foregroundStyle(Palette.accent)
            VStack(spacing: 4) {
                Text("Open source under the MIT Licence.")
                Text("OctoMac is independent and isn't affiliated with OctoPrint.")
            }
            .font(Typeface.caption).foregroundStyle(Palette.faint)
            .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(width: 420)
        .background(Palette.graphite)
        .containerBackground(Palette.graphite, for: .window)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

/// Help → Report a Problem…: shows the diagnostics file before anything leaves the Mac, and points to GitHub issues,
/// the only place bug reports go.
struct ReportProblemView: View {
    @Environment(InstanceStore.self) private var store
    @State private var text = ""
    @State private var saved: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Report a problem").font(Typeface.title).foregroundStyle(Palette.paper)
            Text("Bug reports go on GitHub as public issues, and only there. Below is a diagnostics file you can attach. It leaves out printer names and addresses, API keys, user names and file names. Read it first, and only share it if you're happy to. Nothing is sent automatically.")
                .font(Typeface.body).foregroundStyle(Palette.dust)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Palette.dust)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.extrusion))

            HStack(spacing: 10) {
                Button { save() } label: { Label("Save diagnostics…", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.plateQuiet)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(.plateQuiet)
                if let saved {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([saved]) }
                        .buttonStyle(.plateQuiet)
                }
                Spacer()
                Button { NSWorkspace.shared.open(Diagnostics.newIssueURL) } label: {
                    Label("Open a GitHub issue", systemImage: "arrow.up.right")
                }
                .buttonStyle(.plate)
            }
            Text("Please don't paste API keys, passwords or printer addresses into the issue. Issues can be read by anyone.")
                .font(Typeface.caption).foregroundStyle(Palette.faint)
        }
        .padding(26)
        .frame(minWidth: 640, minHeight: 520)
        .background(Palette.graphite)
        .containerBackground(Palette.graphite, for: .window)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .task {
            let status = await Notifier.shared.permissionStatus()
            text = Diagnostics.report(store: store, notifications: status)
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "OctoMac diagnostics.txt")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
        saved = url
    }
}

/// Settings → General.
struct GeneralSettings: View {
    @AppStorage(TemperatureUnit.defaultsKey) private var unit = TemperatureUnit.celsius.rawValue
    @AppStorage(DockProgress.defaultsKey) private var dockProgress = true
    /// "" follows macOS.
    @State private var language = AppLanguage.chosen ?? ""
    @State private var showing = AppLanguage.chosen ?? ""
    @State private var checksAutomatically = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Temperatures").font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                    Text("Printers always work in Celsius; this only changes what OctoMac shows.")
                        .font(Typeface.caption).foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                CapsulePicker(selection: $unit, options: TemperatureUnit.allCases.map { ($0.rawValue, $0.title) })
            }
            .padding(14)
            .machined(radius: 12)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Language").font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                    Text(language == showing ? "OctoMac follows your Mac's language unless you choose one here."
                                             : "OctoMac needs to restart to switch language.")
                        .font(Typeface.caption).foregroundStyle(language == showing ? Palette.faint : Palette.warm)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if language != showing {
                    Button("Restart now") { AppLanguage.restart() }
                        .buttonStyle(.plate)
                        .controlSize(.small)
                }
                PlateMenu(selection: Binding(get: { language }, set: { code in
                    language = code
                    AppLanguage.chosen = code.isEmpty ? nil : code
                }), options: [("", String(localized: "Same as macOS"))] + AppLanguage.available.map { ($0.code, $0.name) })
                .frame(width: 190)
            }
            .padding(14)
            .machined(radius: 12)

            Toggle(isOn: $dockProgress) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show progress on the Dock icon").font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                    Text("A bar for the print that finishes soonest, amber while it's paused.")
                        .font(Typeface.caption).foregroundStyle(Palette.faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .tint(Palette.accent)
            .padding(14)
            .machined(radius: 12)

            if Updates.shared.isAvailable {
                HStack {
                    Toggle(isOn: Binding(get: { checksAutomatically }, set: {
                        checksAutomatically = $0
                        Updates.shared.checksAutomatically = $0
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check for updates automatically").font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                            Text("OctoMac looks for a new version once a day and asks before installing it.")
                                .font(Typeface.caption).foregroundStyle(Palette.faint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                    .tint(Palette.accent)
                    Button("Check now") { Updates.shared.checkForUpdates() }
                        .buttonStyle(.plateQuiet)
                        .controlSize(.small)
                        .disabled(!Updates.shared.canCheck)
                }
                .padding(14)
                .machined(radius: 12)
            }
        }
        .onAppear { checksAutomatically = Updates.shared.checksAutomatically }
    }
}
