import OctoPrintKit
import SwiftUI

// MARK: - Layer stack (the signature progress gauge)

/// Job progress drawn as the side of a print: a column of layer lines that fills from the bottom
/// in the printer's filament colour, with the layer being printed right now glowing.
struct LayerStack: View {
    var fraction: Double
    var filament: Color
    var active: Bool
    var layers = 56

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { timeline in
            Canvas { context, size in
                let pitch = size.height / CGFloat(layers)
                let thickness = max(1.5, pitch * 0.62)
                let filled = Int((Double(layers) * max(0, min(1, fraction))).rounded(.down))
                let phase = timeline.date.timeIntervalSinceReferenceDate

                for index in 0..<layers {
                    // index 0 is the bottom layer
                    let y = size.height - CGFloat(index + 1) * pitch + (pitch - thickness) / 2
                    // Slight width wobble so it reads as extruded plastic, not a bar chart.
                    var generator = SeededGenerator(seed: UInt64(index) &* 2654435761)
                    let inset = CGFloat.random(in: 0...3, using: &generator)
                    let rect = CGRect(x: inset, y: y, width: size.width - inset * 2, height: thickness)
                    let path = Path(roundedRect: rect, cornerRadius: thickness / 2)

                    if index < filled {
                        // Older layers sit a touch darker, like they've cooled.
                        let age = Double(filled - index) / Double(max(filled, 1))
                        context.fill(path, with: .color(filament.opacity(1 - age * 0.35)))
                    } else if index == filled && active && fraction < 1 {
                        let pulse = 0.55 + 0.45 * (0.5 + 0.5 * sin(phase * 3))
                        var glow = context
                        glow.addFilter(.blur(radius: 6))
                        glow.fill(path, with: .color(Palette.hot.opacity(0.7 * pulse)))
                        context.fill(path, with: .color(Palette.warm.mix(with: .white, by: 0.25).opacity(pulse)))
                    } else {
                        context.fill(path, with: .color(Palette.edge.opacity(0.45)))
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Print progress")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

// MARK: - Heat tile

struct HeatTile: View {
    let session: PrinterSession
    let key: String
    let data: TemperatureData
    @State private var editing = false
    @State private var hovering = false

    private var kind: HeaterKind { HeaterKind(key: key) }

    var body: some View {
        Button { editing = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: kind == .bed ? "square.3.layers.3d.bottom.filled" : kind == .chamber ? "cube.transparent" : "flame.fill")
                        .foregroundStyle(Palette.heat(data.actual))
                    Text(kind.displayName).font(Typeface.bodyStrong).foregroundStyle(Palette.dust)
                    Spacer()
                    // Always visible so the tile reads as clickable.
                    Label("Set target", systemImage: "slider.horizontal.3")
                        .font(Typeface.text(11, .demibold))
                        .foregroundStyle(hovering ? Palette.graphite : Palette.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(hovering ? Palette.accent : Palette.accent.opacity(0.14)))
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(data.actual.map { String(format: "%.0f", $0) } ?? "–")
                        .font(Typeface.number(44))
                        .foregroundStyle(Palette.paper)
                        .contentTransition(.numericText(value: data.actual ?? 0))
                    Text("°C").font(Typeface.number(16)).foregroundStyle(Palette.faint)
                    Spacer()
                    if let target = data.target, target > 0 {
                        Text("to \(Int(target))°").font(Typeface.number(17)).foregroundStyle(Palette.dust)
                    } else {
                        Text("off").font(Typeface.text(13, .medium)).foregroundStyle(Palette.faint)
                    }
                }
                HeatBar(actual: data.actual, target: data.target)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .machined(radius: 14, fill: hovering ? Palette.extrusionHi : Palette.extrusion)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(!session.flags.operational)
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            HeatEditor(session: session, key: key, current: data.target ?? 0) { editing = false }
        }
        .animation(.snappy, value: data.actual)
    }
}

/// Track from 0–300°C with the actual temperature as a heat-coloured fill and the target as a notch.
struct HeatBar: View {
    var actual: Double?
    var target: Double?
    var scale: Double = 300

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.graphite)
                Capsule()
                    .fill(LinearGradient(colors: [Palette.cold, Palette.heat(actual)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, width * min(1, (actual ?? 0) / scale)))
                if let target, target > 0 {
                    Rectangle()
                        .fill(Palette.paper)
                        .frame(width: 2, height: 12)
                        .offset(x: width * min(1, target / scale) - 1)
                }
            }
        }
        .frame(height: 6)
    }
}

struct HeatEditor: View {
    let session: PrinterSession
    let key: String
    let current: Double
    let done: () -> Void
    @State private var value: Double = 0

    private var kind: HeaterKind { HeaterKind(key: key) }

    private var presets: [Double] {
        let fromSettings = session.temperaturePresets.map { kind == .bed ? $0.bed : $0.extruder }
        let fallback: [Double] = kind == .bed ? [60, 70, 85, 100] : kind == .chamber ? [35, 45, 55] : [200, 215, 240, 260]
        let combined = (fromSettings.isEmpty ? fallback : fromSettings).filter { $0 > 0 }
        return Array(Set(combined)).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(kind.displayName) target").font(Typeface.subhead).foregroundStyle(Palette.paper)
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(value))").font(Typeface.number(40)).foregroundStyle(Palette.heat(value))
                Text("°C").font(Typeface.number(16)).foregroundStyle(Palette.faint)
            }
            Slider(value: $value, in: 0...(kind == .bed ? 120 : kind == .chamber ? 80 : 300), step: 5)
                .tint(Palette.heat(value))
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { preset in
                    Chip(title: "\(Int(preset))°", selected: value == preset) { value = preset }
                }
            }
            HStack {
                Button("Turn off") { session.setTarget(0, heater: key); done() }
                    .buttonStyle(.plateQuiet)
                Spacer()
                Button("Heat to \(Int(value))°") { session.setTarget(value, heater: key); done() }
                    .buttonStyle(.plate(Palette.heat(value)))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(Palette.extrusion)
        .onAppear { value = current > 0 ? current : (presets.first ?? 0) }
    }
}

// MARK: - Status

enum PrinterMood {
    case printing, paused, ready, idle, busy, error, offline, locked

    @MainActor init(_ session: PrinterSession) {
        switch session.link {
        case .needsAPIKey: self = .locked
        case .connecting, .offline: self = .offline
        case .online:
            let flags = session.flags
            if flags.error { self = .error }
            else if flags.paused || flags.pausing { self = .paused }
            else if flags.printing || flags.cancelling || flags.finishing || flags.resuming { self = .printing }
            else if flags.operational { self = .ready }
            else if session.state?.text.localizedCaseInsensitiveContains("error") == true { self = .error }
            else { self = .idle }
        }
    }

    func color(filament: Color) -> Color {
        switch self {
        case .printing: filament
        case .paused: Palette.warm
        case .ready: Palette.ready
        case .idle: Palette.dust
        case .busy: Palette.warm
        case .error: Palette.hot
        case .offline: Palette.faint
        case .locked: Palette.warm  // needs attention, not "all good"
        }
    }
}

/// A status lamp: a small LED with a soft halo when lit.
struct StatusLamp: View {
    let color: Color
    var lit = true

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .background {
                if lit { Circle().fill(color.opacity(0.5)).frame(width: 16, height: 16).blur(radius: 4) }
            }
    }
}

// MARK: - Webcam / build plate stage

struct CameraStage: View {
    let session: PrinterSession
    var radius: CGFloat = 20

    var body: some View {
        ZStack {
            if session.webcamStreamURL != nil {
                WebcamView(streamer: session.camera, transform: session.webcamTransform)
            } else {
                BuildPlateTexture()
                VStack(spacing: 6) {
                    Image(systemName: "web.camera").font(.system(size: 28, weight: .light))
                    Text("No camera on this printer").font(Typeface.bodyStrong)
                    Text("Add one in OctoPrint's webcam settings and it'll appear here.")
                        .font(Typeface.caption)
                }
                .foregroundStyle(Palette.accent)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1)
        }
    }
}
