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
                .frame(minWidth: 1100, minHeight: 720)
                .background(WindowFiller())
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .commands {
            CommandGroup(replacing: .newItem) {}
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
