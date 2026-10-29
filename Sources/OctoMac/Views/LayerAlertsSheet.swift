import OctoPrintKit
import SwiftUI

/// Pause or get a notification when the print reaches a layer: for dropping in magnets or nuts, a colour change,
/// or just keeping an eye on it.
struct LayerAlertsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    let filament: Color
    @State private var layer = 2
    @State private var action = LayerAlert.Action.pause

    private var current: Int { session.layerProgress?.currentLayer ?? 1 }
    private var total: Int { max(current + 1, session.layerProgress?.totalLayers ?? current + 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Layer alerts").font(Typeface.title).foregroundStyle(Palette.paper)
                Spacer()
                Text("Now on layer \(current) of \(total)").font(Typeface.number(13)).foregroundStyle(Palette.faint)
            }
            Text("Pause to drop in magnets, nuts or a new colour, or just get a notification when the print gets there.")
                .font(Typeface.body).foregroundStyle(Palette.dust)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Picker("", selection: $action) {
                    Text("Pause at").tag(LayerAlert.Action.pause)
                    Text("Tell me at").tag(LayerAlert.Action.notify)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Text("layer").font(Typeface.body).foregroundStyle(Palette.dust)
                TextField("", value: $layer, format: .number)
                    .plateField()
                    .frame(width: 80)
                    .onSubmit(add)
                Stepper("", value: $layer, in: (current + 1)...total).labelsHidden()
                Spacer()
                Button("Add", action: add)
                    .buttonStyle(.plate(filament))
                    .disabled(layer <= current || layer > total)
            }

            if session.layerAlerts.isEmpty {
                Text("No alerts yet.").font(Typeface.caption).foregroundStyle(Palette.faint)
            } else {
                VStack(spacing: 0) {
                    ForEach(session.layerAlerts) { alert in
                        HStack(spacing: 12) {
                            Image(systemName: alert.action == .pause ? "pause.circle.fill" : "bell.fill")
                                .foregroundStyle(alert.action == .pause ? Palette.warm : Palette.accent)
                                .frame(width: 20)
                            Text(alert.action == .pause ? "Pause at layer \(alert.layer)" : "Tell me at layer \(alert.layer)")
                                .font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                            Spacer()
                            if let average = session.layerProgress?.averageLayerDuration, average > 0 {
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
                Text("OctoMac needs to be open for these. A pause happens as the layer starts, and alerts are cleared when the print ends.")
                    .font(Typeface.caption).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Button("Done") { dismiss() }.buttonStyle(.plate).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 520)
        .background(Palette.extrusion)
        .onAppear { layer = min(total, current + 1) }
    }

    private func add() {
        guard layer > current, layer <= total else { return }
        session.addLayerAlert(LayerAlert(layer: layer, action: action))
        layer = min(total, layer + 1)
    }
}
