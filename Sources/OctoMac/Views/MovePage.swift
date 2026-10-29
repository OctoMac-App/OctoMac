import OctoPrintKit
import SwiftUI

// MARK: - Move

struct MovePage: View {
    let session: PrinterSession
    @AppStorage("jogStep") private var step = 10.0
    @AppStorage("extrudeAmount") private var extrudeAmount = 5.0
    @State private var fan = 100.0

    private let steps: [Double] = [0.1, 1, 10, 50, 100]

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !session.canControl {
                        StageNotice(text: session.flags.isJobActive
                            ? "Moving the print head is locked while a print is running. Fan and speed still work."
                            : "Connect the printer to move it.")
                    }
                    // Side by side when there's room; stacked on smaller windows.
                    if geo.size.width >= 940 {
                        HStack(alignment: .top, spacing: 20) {
                            printHead.frame(minHeight: max(560, geo.size.height - 80))
                            controls.frame(width: 420)
                        }
                    } else {
                        printHead.frame(height: 540)
                        controls
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var printHead: some View {
StagePanel(title: "Print head", detail: "Step \(Fmt.number(step)) mm", fills: true) {
    VStack(spacing: 28) {
        HStack(alignment: .center, spacing: 48) {
            xyDial
            zColumn
        }
        .frame(maxWidth: .infinity)

        HStack(spacing: 8) {
            ForEach(steps, id: \.self) { value in
                Chip(title: "\(Fmt.number(value)) mm", selected: step == value) { step = value }
            }
        }
        Button { session.home(Axis.allCases) } label: { Label("Home all axes", systemImage: "house.fill") }
            .buttonStyle(.plateQuiet)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
.frame(maxHeight: .infinity)
.disabled(!session.canControl)
    }

    private var controls: some View {
VStack(spacing: 20) {
    StagePanel(title: "Filament") {
        HStack(spacing: 10) {
            TextField("mm", value: $extrudeAmount, format: .number)
                .plateField()
                .frame(width: 80)
            Text(verbatim: "mm").font(Typeface.body).foregroundStyle(Palette.dust)
            Spacer(minLength: 0)
        }
        // On their own line, so longer words in other languages never wrap mid-word.
        HStack(spacing: 10) {
            Button { session.extrude(-extrudeAmount) } label: { Label("Retract", systemImage: "arrow.up").lineLimit(1).fixedSize() }
                .buttonStyle(.plateQuiet)
            Button { session.extrude(extrudeAmount) } label: { Label("Extrude", systemImage: "arrow.down").lineLimit(1).fixedSize() }
                .buttonStyle(.plate)
            Spacer(minLength: 0)
        }
        Text("The hotend has to be hot before the printer will push filament.")
            .font(Typeface.caption).foregroundStyle(Palette.faint)
    }
    .disabled(!session.canControl)

    StagePanel(title: "Fan and speed") {
        VStack(spacing: 18) {
            dialRow("Part fan", value: $fan, range: 0...100, step: 5, unit: "%") { session.setFan(percent: fan) }
            dialRow("Print speed", value: rate(\.feedRate), range: 50...200, step: 5, unit: "%") { session.setFeedRate(Int(session.feedRate)) }
            dialRow("Flow", value: rate(\.flowRate), range: 75...125, step: 1, unit: "%") { session.setFlowRate(Int(session.flowRate)) }
        }
    }
    .disabled(!session.flags.operational)

    StagePanel(title: "Quick commands") {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            quick("Motors off", "M18", "power")
            quick("Fan off", "M107", "fan.slash")
            quick("Report position", "M114", "location")
            quick("Firmware info", "M115", "info.circle")
            quick("Bed mesh", "M420 V", "square.grid.3x3")
            quick("Save to EEPROM", "M500", "square.and.arrow.down")
        }
    }
    .disabled(!session.flags.operational)

    if !session.customControls.isEmpty {
        CustomControlsPanel(session: session)
    }
}
    }

    private var xyDial: some View {
        ZStack {
            Circle().fill(Palette.graphite).frame(width: 300, height: 300)
            Circle().strokeBorder(Palette.edge, lineWidth: 1).frame(width: 300, height: 300)
            Circle().strokeBorder(Palette.edge.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 5])).frame(width: 190, height: 190)
            VStack(spacing: 0) {
                Button { session.jog(y: step) } label: { Image(systemName: "chevron.up") }.buttonStyle(.key).help("Y+")
                Spacer()
                Button { session.jog(y: -step) } label: { Image(systemName: "chevron.down") }.buttonStyle(.key).help("Y−")
            }
            .frame(height: 270)
            HStack(spacing: 0) {
                Button { session.jog(x: -step) } label: { Image(systemName: "chevron.left") }.buttonStyle(.key).help("X−")
                Spacer()
                Button { session.jog(x: step) } label: { Image(systemName: "chevron.right") }.buttonStyle(.key).help("X+")
            }
            .frame(width: 270)
            Button { session.home([.x, .y]) } label: { Image(systemName: "house.fill") }
                .buttonStyle(KeyButtonStyle(size: CGSize(width: 64, height: 64)))
                .help("Home X and Y")
            axisLabel("X", x: 128, y: 0)
            axisLabel("Y", x: 0, y: -128)
        }
    }

    private var zColumn: some View {
        VStack(spacing: 10) {
            Text("Z").font(Typeface.number(15)).foregroundStyle(Palette.faint)
            Button { session.jog(z: step) } label: { Image(systemName: "chevron.up.2") }.buttonStyle(.key).help("Raise Z")
            Button { session.home([.z]) } label: { Image(systemName: "house.fill") }.buttonStyle(.key).help("Home Z")
            Button { session.jog(z: -step) } label: { Image(systemName: "chevron.down.2") }.buttonStyle(.key).help("Lower Z")
        }
        .padding(14)
        .background(Capsule().fill(Palette.graphite))
        .overlay(Capsule().strokeBorder(Palette.edge, lineWidth: 1))
    }

    private func axisLabel(_ text: String, x: CGFloat, y: CGFloat) -> some View {
        Text(text).font(Typeface.number(11)).foregroundStyle(Palette.faint).offset(x: x + (x > 0 ? 8 : 0), y: y - (y < 0 ? 8 : 0))
    }

    /// Speed and flow live on the session, so the Overview's controls and these sliders agree.
    private func rate(_ keyPath: ReferenceWritableKeyPath<PrinterSession, Double>) -> Binding<Double> {
        Binding(get: { session[keyPath: keyPath] }, set: { session[keyPath: keyPath] = $0 })
    }

    private func dialRow(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String, apply: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.dust)
                .lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                .frame(width: 118, alignment: .leading)
            Slider(value: value, in: range, step: step) { editing in if !editing { apply() } }
                .tint(Palette.accent)
            Text(unit == "%" ? (value.wrappedValue / 100).formatted(.percent.precision(.fractionLength(0))) : "\(Int(value.wrappedValue))\(unit)")
                .font(Typeface.number(17))
                .foregroundStyle(Palette.paper)
                .frame(width: 54, alignment: .trailing)
        }
    }

    private func quick(_ title: LocalizedStringKey, _ gcode: String, _ symbol: String) -> some View {
        Button { session.sendGcode(gcode) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(Palette.accent).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Typeface.text(12, .demibold)).foregroundStyle(Palette.paper)
                    Text(gcode).font(Typeface.number(11)).foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .machined(radius: 10, fill: Palette.graphite)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
