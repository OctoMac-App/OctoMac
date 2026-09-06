import AppKit
import Observation
import OctoPrintKit
import SwiftUI

/// A small floating camera window that stays above other apps (picture in picture). It shows the same stream as the
/// main window, so popping out never opens a second connection; the main window shows a placeholder meanwhile.
@MainActor
@Observable
final class PictureInPicture {
    static let shared = PictureInPicture()

    /// The printer whose camera is popped out, if any.
    private(set) var sessionID: UUID?
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var closeObserver: NSObjectProtocol?

    private static let autosaveName = "OctoMacPictureInPicture.v2"
    /// A 16:9 picture (320 × 180) plus the info strip underneath.
    static let defaultSize = NSSize(width: 320, height: 180 + PictureInPictureView.stripHeight)

    func show(_ session: PrinterSession, filament: Color) {
        close()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.defaultSize.width, height: Self.defaultSize.height),
                            styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = NSSize(width: 240, height: 176)
        panel.maxSize = NSSize(width: 1280, height: 780)
        panel.contentView = NSHostingView(rootView: PictureInPictureView(session: session, filament: filament))

        // Bottom right of the screen the first time; wherever you left it after that.
        if !panel.setFrameUsingName(Self.autosaveName), let screen = NSScreen.main {
            let area = screen.visibleFrame
            let size = Self.defaultSize
            panel.setFrame(NSRect(x: area.maxX - size.width - 24, y: area.minY + 24, width: size.width, height: size.height), display: true)
        }
        panel.setFrameAutosaveName(Self.autosaveName)
        panel.orderFrontRegardless()

        self.panel = panel
        sessionID = session.instance.id
    }

    func close() {
        panel?.saveFrame(usingName: Self.autosaveName)
        panel?.orderOut(nil)
        panel = nil
        sessionID = nil
    }

    /// Closes the floating window and brings OctoMac forward.
    func returnToApp() {
        close()
        NSApp.activate()
    }
}

struct PictureInPictureView: View {
    let session: PrinterSession
    let filament: Color
    @State private var hovering = false

    static let stripHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            WebcamView(streamer: session.camera, transform: session.webcamTransform)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    if hovering {
                        HStack(spacing: 6) {
                            pipButton("pip.exit", help: "Back to OctoMac") { PictureInPicture.shared.returnToApp() }
                            pipButton("xmark", help: "Close") { PictureInPicture.shared.close() }
                        }
                        .padding(8)
                        .transition(.opacity)
                    }
                }
            infoStrip
        }
        .background(Palette.rail)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onTapGesture(count: 2) { PictureInPicture.shared.returnToApp() }
    }

    private var infoStrip: some View {
        VStack(spacing: 0) {
            // Thin progress line in the printer's colour while printing.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.edge.opacity(0.5))
                    if session.flags.isJobActive, let fraction = session.progress?.fraction {
                        Rectangle().fill(filament).frame(width: geo.size.width * fraction)
                    }
                }
            }
            .frame(height: 3)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.instance.name).font(Typeface.text(12, .demibold)).foregroundStyle(Palette.paper).lineLimit(1)
                    Group {
                        if session.flags.isJobActive, let fraction = session.progress?.fraction {
                            Text("\(Int(fraction * 100))%, \(Fmt.duration(session.progress?.printTimeLeft)) left")
                                .font(Typeface.number(11))
                        } else {
                            Text(session.stateText).font(Typeface.caption)
                        }
                    }
                    .foregroundStyle(Palette.dust)
                    .lineLimit(1)
                }
                Spacer(minLength: 6)
                ForEach(temperatureKeys, id: \.self) { key in
                    let kind = HeaterKind(key: key)
                    HStack(spacing: 3) {
                        Image(systemName: kind.symbol).font(.system(size: 9)).foregroundStyle(kind.color)
                        Text(Fmt.deg(session.heaters[key]?.actual))
                            .font(Typeface.number(13)).foregroundStyle(Palette.paper)
                    }
                    .fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: Self.stripHeight - 3)
        }
    }

    /// The main hotend and the bed (plus a chamber if there is one), to keep the strip short.
    private var temperatureKeys: [String] {
        ["tool0", "bed", "chamber"].filter { session.heaters[$0]?.actual != nil }
    }

    private func pipButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.black.opacity(0.5)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
