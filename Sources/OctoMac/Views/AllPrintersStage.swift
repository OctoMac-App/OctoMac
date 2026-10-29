import OctoPrintKit
import SwiftUI

/// "All printers": every printer's camera, progress and temperatures side by side.
enum AllPrinters {
    /// Stands in for a printer in the sidebar selection.
    static let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
}

struct AllPrintersStage: View {
    @Environment(InstanceStore.self) private var store
    @Binding var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("All printers").font(Typeface.display).foregroundStyle(Palette.paper)
                Text(summary).font(Typeface.bodyStrong).foregroundStyle(Palette.dust)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 18)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 20, alignment: .top)], spacing: 20) {
                    ForEach(store.instances) { instance in
                        if let session = store.sessions[instance.id] {
                            PrinterCard(session: session, filament: store.filament(for: instance)) {
                                selection = instance.id
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
    }

    private var summary: String {
        let sessions = store.instances.compactMap { store.sessions[$0.id] }
        let printing = sessions.filter { $0.flags.isJobActive }.count
        let ready = sessions.filter { PrinterMood($0) == .ready }.count
        var parts: [String] = []
        if printing > 0 { parts.append(String(localized: "\(printing) printing")) }
        if ready > 0 { parts.append(String(localized: "\(ready) ready")) }
        let other = sessions.count - printing - ready
        if other > 0 { parts.append(String(localized: "\(other) not connected")) }
        return parts.formatted(.list(type: .and, width: .narrow))
    }
}

/// One printer in the grid. Click it to open that printer.
private struct PrinterCard: View {
    let session: PrinterSession
    let filament: Color
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        let mood = PrinterMood(session)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Group {
                        if session.link == .online, session.webcamStreamURL != nil {
                            WebcamView(streamer: session.camera, transform: session.webcamTransform)
                                .onAppear { session.camera.addViewer() }
                                .onDisappear { session.camera.removeViewer() }
                        } else {
                            ZStack {
                                Palette.graphite
                                Image(systemName: session.link == .online ? "web.camera" : "wifi.slash")
                                    .font(.system(size: 26)).foregroundStyle(Palette.faint)
                            }
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    HStack(spacing: 7) {
                        StatusLamp(color: mood.color(filament: filament), lit: mood != .offline)
                        Text(session.instance.name).font(Typeface.text(14, .demibold)).foregroundStyle(.white).lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(10)
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    if mood == .printing || mood == .paused, let fraction = session.progress?.fraction {
                        HStack(alignment: .firstTextBaseline) {
                            Text(SlicedName(session.job?.file.displayName ?? "").title)
                                .font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(Int(fraction * 100))%").font(Typeface.number(22)).foregroundStyle(Palette.paper)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette.edge)
                                Capsule().fill(mood == .paused ? Palette.warm : filament).frame(width: max(4, geo.size.width * fraction))
                            }
                        }
                        .frame(height: 6)
                        HStack {
                            Text(mood == .paused ? "Paused" : "\(Fmt.duration(session.progress?.printTimeLeft)) left")
                            Spacer()
                            Text("Done at \(Fmt.eta(session.progress?.printTimeLeft))")
                        }
                        .font(Typeface.caption).foregroundStyle(Palette.dust)
                    } else {
                        Text(session.stateText).font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(1)
                    }
                    temperatures
                }
                .padding(14)
            }
            .machined(radius: 16, fill: hovering ? Palette.extrusionHi : Palette.extrusion)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open \(session.instance.name)")
    }

    private func readings(_ keys: [String], targets: Bool) -> some View {
        HStack(spacing: 14) {
            ForEach(keys, id: \.self) { key in
                let data = session.heaters[key]
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: HeaterKind(key: key).symbol).font(.system(size: 10)).foregroundStyle(HeaterKind(key: key).color)
                    Text(Fmt.deg(data?.actual)).font(Typeface.number(15)).foregroundStyle(Palette.paper)
                    if targets, let target = data?.target, target > 0 {
                        Text("→ \(Fmt.deg(target))").font(Typeface.number(12)).foregroundStyle(Palette.faint)
                    }
                }
                .fixedSize()
                .help(HeaterKind(key: key).displayName)
            }
        }
    }

    @ViewBuilder private var temperatures: some View {
        let keys = session.heaters.filter { HeaterKind(key: $0.key).isHeater && $0.value.actual != nil }.keys.sorted()
        if !keys.isEmpty {
            // With targets when they fit; just the readings on printers with many heaters.
            ViewThatFits(in: .horizontal) {
                readings(keys, targets: true)
                readings(keys, targets: false)
            }
        }
    }
}
