import OctoPrintKit
import SwiftUI

/// How OctoPrint makes timelapses: when it takes a picture, how fast the video plays, and which prints get one.
/// Saved as OctoPrint's default, so it applies to every print from the next one on.
struct TimelapseSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    @State private var settings: TimelapseSettings

    init(session: PrinterSession) {
        self.session = session
        _settings = State(initialValue: session.timelapses?.settings ?? TimelapseSettings())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timelapse settings").font(Typeface.title).foregroundStyle(Palette.paper)
                Text("OctoPrint takes the pictures from the printer's camera and turns them into a video when the print ends. Changes apply from the next print.")
                    .font(Typeface.body).foregroundStyle(Palette.dust)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CapsulePicker(selection: $settings.mode, options: [(.off, "Off"), (.zchange, "On layer change"), (.timed, "Timed")])

            if settings.mode != .off {
                VStack(spacing: 10) {
                    switch settings.mode {
                    case .zchange:
                        row("At most one picture every", detail: "Stops tiny layers or vase mode filling the video.",
                            value: $settings.minDelay, unit: "s", range: 0...60, step: 1)
                        row("Ignore Z hops up to", detail: "If your slicer lifts the nozzle when it retracts, set this to that height so a hop isn't taken as a new layer.",
                            value: $settings.retractionZHop, unit: "mm", range: 0...5, step: 0.1)
                    case .timed:
                        row("A picture every", detail: nil, value: intBinding(\.interval), unit: "s", range: 1...600, step: 1)
                    case .off:
                        EmptyView()
                    }
                    row("Frames per second", detail: "Higher plays the video faster.", value: intBinding(\.fps), unit: nil, range: 1...60, step: 1)
                    row("Hold the last frame for", detail: "Shows the finished print at the end of the video.",
                        value: intBinding(\.postRoll), unit: "s", range: 0...30, step: 1)
                    HStack(spacing: 12) {
                        Text("Make a video for").font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                        Spacer()
                        PlateMenu(selection: $settings.render, options: [
                            (.always, String(localized: "Every print")),
                            (.success, String(localized: "Finished prints")),
                            (.failure, String(localized: "Failed prints")),
                            (.never, String(localized: "No prints, I'll make them myself")),
                        ])
                        .frame(width: 250)
                    }
                    .padding(12)
                    .machined(radius: 12, fill: Palette.graphite)
                }
                .transition(.opacity)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plateQuiet).keyboardShortcut(.cancelAction)
                Button("Save") {
                    session.saveTimelapseSettings(settings)
                    dismiss()
                }
                .buttonStyle(.plate)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 520)
        .background(Palette.extrusion)
        .animation(.easeOut(duration: 0.2), value: settings.mode)
    }

    private func intBinding(_ path: WritableKeyPath<TimelapseSettings, Int>) -> Binding<Double> {
        Binding(get: { Double(settings[keyPath: path]) }, set: { settings[keyPath: path] = Int($0.rounded()) })
    }

    private func row(_ title: LocalizedStringKey, detail: LocalizedStringKey?, value: Binding<Double>, unit: String?,
                     range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                if let detail {
                    Text(detail).font(Typeface.caption).foregroundStyle(Palette.faint).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            TextField("", value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }),
                      format: .number.precision(.fractionLength(0...1)))
                .plateField()
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            // Every box lines up, with or without a unit beside it.
            Text(verbatim: unit ?? "").font(Typeface.body).foregroundStyle(Palette.dust).frame(width: 24, alignment: .leading)
            Stepper("", value: value, in: range, step: step).labelsHidden()
        }
        .padding(12)
        .machined(radius: 12, fill: Palette.graphite)
    }
}
