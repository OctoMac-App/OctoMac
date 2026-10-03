import AppKit
import Foundation
import OctoPrintKit
import WidgetData
import WidgetKit

/// Keeps the desktop and Control Centre widgets up to date: every few seconds it writes a small status file, and
/// asks WidgetKit to redraw when something you'd notice has changed (a print starting or finishing, the percentage
/// moving, a printer going offline). Demo mode leaves your widgets alone.
@MainActor
final class WidgetFeed {
    static let shared = WidgetFeed()

    private weak var store: InstanceStore?
    private var timer: Timer?
    private var lastWritten: WidgetSnapshot?
    private var lastReload = Date.distantPast
    private var lastCamera = Date.distantPast

    func start(store: InstanceStore) {
        self.store = store
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated { WidgetFeed.shared.update() }
        }
        update()
    }

    private func update() {
        guard let store, !store.isDemo else { return }
        let snapshot = Self.snapshot(of: store)
        if Date.now.timeIntervalSince(lastCamera) > 60 {
            lastCamera = .now
            for instance in store.instances {
                guard let frame = store.sessions[instance.id]?.camera.latestFrameData else { continue }
                Self.writeCamera(frame, to: WidgetSnapshot.cameraURL(for: instance.id))
            }
        }
        let changed = lastWritten.map { !Self.sameAtAGlance($0, snapshot) } ?? true
        guard changed || Date.now.timeIntervalSince(lastReload) > 300 else { return }
        do {
            try snapshot.save()
            lastWritten = snapshot
            lastReload = .now
            WidgetCenter.shared.reloadAllTimelines()
            if #available(macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
        } catch {
            // Widgets are a nice extra; never bother anyone about them.
        }
    }

    static func snapshot(of store: InstanceStore) -> WidgetSnapshot {
        let printers = store.instances.map { instance -> WidgetSnapshot.Printer in
            let session = store.sessions[instance.id]
            let flags = session?.flags ?? PrinterStateFlags()
            let status: WidgetSnapshot.Status
            if session?.link != .online || !(session?.isPrinterConnected ?? false) {
                status = session?.printerFault == true ? .problem : .offline
            } else if flags.paused || flags.pausing {
                status = .paused
            } else if flags.isJobActive {
                status = .printing
            } else {
                status = .ready
            }
            let active = status == .printing || status == .paused
            let tool = session?.heaters["tool0"], bed = session?.heaters["bed"]
            return WidgetSnapshot.Printer(
                id: instance.id, name: instance.name, colorHex: instance.filamentHex, status: status,
                statusText: status == .ready ? "Ready" : (session?.stateText ?? "Offline"),
                job: active ? session?.job?.file.displayName.map { SlicedName($0).title } : nil,
                progress: active ? session?.progress?.fraction : nil,
                timeLeft: active ? session?.progress?.printTimeLeft : nil,
                hotend: tool?.actual, hotendTarget: tool?.target, bed: bed?.actual, bedTarget: bed?.target,
                hasCamera: FileManager.default.fileExists(atPath: WidgetSnapshot.cameraURL(for: instance.id).path))
        }
        return WidgetSnapshot(written: .now, printers: printers, temperatureUnit: TemperatureUnit.current.rawValue)
    }

    /// Whether two snapshots would look the same in a widget: same states and jobs, same whole percentage,
    /// temperatures within a couple of degrees.
    private static func sameAtAGlance(_ a: WidgetSnapshot, _ b: WidgetSnapshot) -> Bool {
        guard a.printers.count == b.printers.count, a.temperatureUnit == b.temperatureUnit else { return false }
        return zip(a.printers, b.printers).allSatisfy { x, y in
            x.id == y.id && x.name == y.name && x.status == y.status && x.statusText == y.statusText && x.job == y.job
                && x.colorHex == y.colorHex && x.hasCamera == y.hasCamera
                && Int((x.progress ?? -1) * 100) == Int((y.progress ?? -1) * 100)
                && abs((x.hotend ?? 0) - (y.hotend ?? 0)) < 3 && abs((x.bed ?? 0) - (y.bed ?? 0)) < 3
        }
    }

    private static func writeCamera(_ frame: Data, to url: URL) {
        guard let image = NSImage(data: frame), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let width = 480, height = Int(Double(cg.height) * 480 / Double(max(cg.width, 1)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage(),
              let jpeg = NSBitmapImageRep(cgImage: small).representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? jpeg.write(to: url, options: .atomic)
    }
}
