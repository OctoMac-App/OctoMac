import OctoPrintKit
import SwiftUI

/// Pause or get a notification when the print reaches a layer: for dropping in magnets or nuts, a colour change,
/// or just keeping an eye on it. Set them while printing or before, and they're saved with the file for next time.
struct LayerAlertsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    let filament: Color
    @State private var layer = 2
    @State private var action = LayerAlert.Action.pause
    /// Pause with the printer's own pause and resume from its knob (Prusa firmware), rather than from OctoMac.
    @AppStorage("layerAlerts.resumeOnPrinter") private var resumeOnPrinter = true

    private var printing: Bool { session.flags.isJobActive }
    /// The layer being printed, or 1 before the print starts (no alert makes sense on the first layer).
    private var current: Int { printing ? session.layerProgress?.currentLayer ?? 1 : 1 }
    /// The file's layer count, once the print has started; before that, any layer.
    private var total: Int {
        guard printing, let count = session.layerProgress?.totalLayers else { return 9_999 }
        return max(current + 1, count)
    }
    private var chosenAction: LayerAlert.Action {
        action == .pause && resumeOnPrinter && session.canPauseOnPrinter ? .pauseOnPrinter : action
    }

    private var actionPicker: some View {
        CapsulePicker(selection: $action, options: [(.pause, "Pause at"), (.notify, "Tell me at")]).fixedSize()
    }

    private var layerField: some View {
        HStack(spacing: 10) {
            Text("layer").font(Typeface.body).foregroundStyle(Palette.dust).lineLimit(1).fixedSize()
            TextField("", value: $layer, format: .number)
                .plateField()
                .frame(width: 80)
                .onSubmit(add)
            Stepper("", value: $layer, in: (current + 1)...total).labelsHidden()
        }
    }

    private var addButton: some View {
        Button(action: add) { Text("Add").lineLimit(1).fixedSize() }
            .buttonStyle(.plate(filament))
            .disabled(layer <= current || layer > total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Layer alerts").font(Typeface.title).foregroundStyle(Palette.paper)
                Spacer()
                if printing, let count = session.layerProgress?.totalLayers {
                    Text("Now on layer \(current) of \(count)").font(Typeface.number(13)).foregroundStyle(Palette.faint)
                }
            }
            Text(printing
                 ? "Pause to drop in magnets, nuts or a new colour, or just get a notification when the print gets there."
                 : "Pause to drop in magnets, nuts or a new colour, or just get a notification when the print gets there. Use the layer numbers from your slicer's preview.")
                .font(Typeface.body).foregroundStyle(Palette.dust)
                .fixedSize(horizontal: false, vertical: true)

            // On one line when it fits; in longer languages the layer and Add go underneath.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    actionPicker
                    layerField
                    Spacer(minLength: 0)
                    addButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    actionPicker
                    HStack(spacing: 10) {
                        layerField
                        Spacer(minLength: 0)
                        addButton
                    }
                }
            }

            if action == .pause, session.canPauseOnPrinter {
                Toggle(isOn: $resumeOnPrinter) {
                    Text("Resume from the printer's knob").font(Typeface.body).foregroundStyle(Palette.paper)
                }
                .toggleStyle(.checkbox)
                .help("The printer pauses itself (M601): it parks the nozzle and waits until you choose Resume on its screen.")
            }

            if session.layerAlerts.isEmpty {
                Text("No alerts yet.").font(Typeface.caption).foregroundStyle(Palette.faint)
            } else {
                VStack(spacing: 0) {
                    ForEach(session.layerAlerts) { alert in
                        let done = printing && (session.firedLayerAlerts.contains(alert.id) || alert.layer <= current)
                        HStack(spacing: 12) {
                            Image(systemName: alert.action == .notify ? "bell.fill" : "pause.circle.fill")
                                .foregroundStyle(done ? Palette.faint : alert.action == .notify ? Palette.accent : Palette.warm)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(alert.action == .notify ? "Tell me at layer \(alert.layer)" : "Pause at layer \(alert.layer)")
                                    .font(Typeface.bodyStrong).foregroundStyle(done ? Palette.dust : Palette.paper)
                                if alert.action == .pauseOnPrinter {
                                    Text("Resume from the printer").font(Typeface.caption).foregroundStyle(Palette.faint)
                                }
                            }
                            Spacer()
                            if done {
                                Text("Done").font(Typeface.caption).foregroundStyle(Palette.faint)
                            } else if printing, let average = session.layerProgress?.averageLayerDuration, average > 0 {
                                Text("in about \(Fmt.duration(Double(alert.layer - current) * average))")
                                    .font(Typeface.caption).foregroundStyle(Palette.faint)
                            }
                            Button { session.removeLayerAlert(alert) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .foregroundStyle(Palette.faint)
                                .help("Remove this alert")
                        }
                        .padding(.vertical, 9)
                        if alert.id != session.layerAlerts.last?.id { Divider().overlay(Palette.edge) }
                    }
                }
                .padding(.horizontal, 14)
                .machined(radius: 12, fill: Palette.graphite)
            }

            HStack(alignment: .top) {
                Text("OctoMac needs to be open for these, and a pause happens as the layer starts. They're saved with the file, ready for the next time you print it.")
                    .font(Typeface.caption).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Button("Done") { dismiss() }.buttonStyle(.plate).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 520)
        .background(Palette.extrusion)
        .onAppear { layer = min(total, max(2, current + 1)) }
    }

    private func add() {
        guard layer > current, layer <= total else { return }
        session.addLayerAlert(LayerAlert(layer: layer, action: chosenAction))
        layer = min(total, layer + 1)
    }
}
