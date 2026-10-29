import AppKit
import SwiftUI

@main
struct OctoMacApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var store = InstanceStore()

    var body: some Scene {
        WindowGroup("OctoMac", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 960, minHeight: 620)
                .background(WindowFiller())
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .importExport) {
                Button("Import Printers…") { PrinterTransfer.importList(into: store) }
                    .disabled(store.isDemo)
                Button("Export Printers…") { PrinterTransfer.export(store) }
                    .disabled(store.isDemo || store.instances.isEmpty)
            }
            CommandGroup(replacing: .appInfo) {
                AboutCommand()
                Button("Check for Updates…") { Updates.shared.checkForUpdates() }
                    .disabled(!Updates.shared.canCheck)
            }
            CommandMenu("Printer") { PrinterCommands(store: store) }
            CommandGroup(replacing: .help) { HelpCommands(store: store) }
        }

        // G-code previews open in their own windows, so they can sit beside the printer view.
        WindowGroup("G-code preview", id: "gcode-preview", for: GCodePreviewRequest.self) { $request in
            if let request {
                GCodePreviewWindow(request: request)
                    .environment(store)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 860)
        // Previews are quick to reopen and may refer to files that have since changed; don't restore them at launch.
        .restorationBehavior(.disabled)

        Window("About OctoMac", id: "about") {
            AboutView().preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("Report a Problem", id: "report") {
            ReportProblemView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(store)
                .preferredColorScheme(.dark)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(store)
                .preferredColorScheme(.dark)
        } label: {
            MenuBarLabel().environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable via `swift run` rather than from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        Notifier.shared.start()
        _ = Updates.shared
    }

    /// G-code opened from Finder or dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { FileInbox.shared.receive(urls) }
    }
}

/// Sizes the main window to fill the screen's usable area (below the menu bar, beside the Dock) on the very
/// first launch, without entering a separate full-screen Space. After that SwiftUI's own window restoration
/// brings back whatever size and position the user chose.
private struct WindowFiller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { FillerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class FillerView: NSView {
        private static let didInitialFillKey = "window.didInitialFill"
        private var configured = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !configured, let window else { return }
            configured = true
            DispatchQueue.main.async {
                window.isMovableByWindowBackground = true
                window.backgroundColor = NSColor(Palette.graphite)
                let defaults = UserDefaults.standard
                guard !defaults.bool(forKey: Self.didInitialFillKey) else { return }
                defaults.set(true, forKey: Self.didInitialFillKey)
                if let screen = window.screen ?? NSScreen.main {
                    window.setFrame(screen.visibleFrame, display: true, animate: false)
                }
            }
        }
    }
}

private struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("About OctoMac") { openWindow(id: "about") } }
}

private struct HelpCommands: View {
    let store: InstanceStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(store.isDemo ? "Exit Demo Mode" : "Try Demo Mode") {
            if store.isDemo { store.exitDemo() } else { store.enterDemo() }
        }
        Divider()
        Button("Report a Problem…") { openWindow(id: "report") }
        Button("OctoMac on GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/OctoMac-App/OctoMac")!) }
        Button("Privacy") { NSWorkspace.shared.open(URL(string: "https://github.com/OctoMac-App/OctoMac/blob/master/PRIVACY.md")!) }
        Divider()
        Button("Support OctoMac") { NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/rogerthomas")!) }
    }
}
