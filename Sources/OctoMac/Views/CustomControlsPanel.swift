import OctoPrintKit
import SwiftUI

/// The buttons set up in OctoPrint's own settings (custom controls), on the Move tab.
struct CustomControlsPanel: View {
    let session: PrinterSession

    var body: some View {
        StagePanel(title: "Your controls", detail: "From OctoPrint") {
            VStack(alignment: .leading, spacing: 16) {
                // Loose controls first, then each named group.
                let loose = session.customControls.compactMap { control -> CustomControl.Action? in
                    if case .action(let action) = control { return action }
                    return nil
                }
                if !loose.isEmpty { ControlGrid(session: session, actions: loose) }
                ForEach(session.customControls) { control in
                    if case .group(let name, let children) = control {
                        ControlGroupView(session: session, name: name, children: children)
                    }
                }
            }
        }
        .disabled(!session.flags.operational)
    }
}

private struct ControlGroupView: View {
    let session: PrinterSession
    let name: String
    let children: [CustomControl]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !name.isEmpty { Text(name).font(Typeface.caption).foregroundStyle(Palette.faint) }
            ControlGrid(session: session, actions: children.compactMap {
                if case .action(let action) = $0 { return action }
                return nil
            })
            ForEach(children) { child in
                if case .group(let childName, let grandchildren) = child {
                    ControlGroupView(session: session, name: childName, children: grandchildren)
                        .padding(.leading, 10)
                }
            }
        }
    }
}

private struct ControlGrid: View {
    let session: PrinterSession
    let actions: [CustomControl.Action]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10, alignment: .bottom)], alignment: .leading, spacing: 10) {
            ForEach(actions) { action in ControlButton(session: session, action: action) }
        }
    }
}

private struct ControlButton: View {
    let session: PrinterSession
    let action: CustomControl.Action
    @State private var values: [String: String] = [:]
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(action.inputs) { input in
                HStack(spacing: 6) {
                    Text(input.name).font(Typeface.caption).foregroundStyle(Palette.faint).lineLimit(1)
                    TextField(input.defaultValue, text: binding(for: input))
                        .plateField()
                        .frame(maxWidth: 90)
                }
            }
            Button {
                if action.confirm != nil { confirming = true } else { run() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: action.script != nil ? "scroll" : "terminal").foregroundStyle(Palette.accent).frame(width: 16)
                    Text(action.name).font(Typeface.text(12, .demibold)).foregroundStyle(Palette.paper).lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .machined(radius: 10, fill: Palette.graphite)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(action.script.map { "Runs the \($0) script" } ?? action.commands.joined(separator: "\n"))
        }
        .sheet(isPresented: $confirming) {
            ConfirmSheet(symbol: "questionmark.circle", tint: Palette.warm, title: "\(action.name)?",
                         message: action.confirm ?? "", confirmTitle: action.name, onConfirm: run)
        }
    }

    private func binding(for input: CustomControl.Input) -> Binding<String> {
        Binding(get: { values[input.parameter] ?? input.defaultValue }, set: { values[input.parameter] = $0 })
    }

    private func run() {
        var filled = values
        for input in action.inputs where filled[input.parameter] == nil { filled[input.parameter] = input.defaultValue }
        session.run(action, values: filled)
    }
}
