import AppKit
import Foundation

/// Draws a progress bar across OctoMac's Dock icon while something is printing: the print that finishes soonest,
/// the same one the menu bar shows. Amber while that print is paused. Switch it off in Settings → General.
@MainActor
final class DockProgress {
    static let shared = DockProgress()
    static let defaultsKey = "dock.progress"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }

    private weak var store: InstanceStore?
    private var timer: Timer?
    private var shown: State?

    private struct State: Equatable {
        var percent: Int
        var paused: Bool
    }

    func start(store: InstanceStore) {
        self.store = store
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { DockProgress.shared.update() }
        }
        update()
    }

    private func update() {
        let state = Self.isEnabled ? store.flatMap(Self.state(of:)) : nil
        guard state != shown else { return }
        shown = state
        let tile = NSApp.dockTile
        if let state {
            let view = (tile.contentView as? TileView) ?? TileView()
            view.fraction = Double(state.percent) / 100
            view.paused = state.paused
            tile.contentView = view
        } else {
            tile.contentView = nil
        }
        tile.display()
    }

    private static func state(of store: InstanceStore) -> State? {
        let active = store.instances.compactMap { store.sessions[$0.id] }.filter { $0.flags.isJobActive && $0.progress?.fraction != nil }
        guard let soonest = active.min(by: { ($0.progress?.printTimeLeft ?? .infinity) < ($1.progress?.printTimeLeft ?? .infinity) }),
              let fraction = soonest.progress?.fraction else { return nil }
        return State(percent: Int((fraction * 100).rounded(.down)), paused: soonest.flags.paused || soonest.flags.pausing)
    }

    /// The app icon with a rounded bar along the bottom.
    private final class TileView: NSView {
        var fraction = 0.0
        var paused = false

        override func draw(_ dirtyRect: NSRect) {
            NSApp.applicationIconImage?.draw(in: bounds)
            let inset = bounds.width * 0.14
            let height = bounds.height * 0.1
            let track = NSRect(x: inset, y: bounds.height * 0.1, width: bounds.width - inset * 2, height: height)
            let radius = height / 2
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: track.insetBy(dx: -2, dy: -2), xRadius: radius + 2, yRadius: radius + 2).fill()
            NSColor.white.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
            var fill = track
            fill.size.width = max(height, track.width * min(max(fraction, 0), 1))
            NSColor(paused ? Palette.warm : Palette.accent).setFill()
            NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
        }
    }
}
