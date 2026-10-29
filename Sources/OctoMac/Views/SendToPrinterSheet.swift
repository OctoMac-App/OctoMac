import OctoPrintKit
import SwiftUI

/// Copies a file from one printer to one or more others, and can start it printing when it goes to just one.
/// OctoMac fetches the file from the first printer and uploads it to each of the others; nothing is left on your Mac.
struct SendToPrinterSheet: View {
    @Environment(InstanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let source: PrinterSession
    let file: FileEntry
    let filament: Color

    @State private var chosen: Set<UUID> = []
    @State private var printNow = false
    @State private var phase = Phase.choosing
    @State private var progress: [UUID: Double] = [:]
    @State private var failures: [UUID: String] = [:]
    @State private var work: Task<Void, Never>?

    enum Phase: Equatable { case choosing, fetching, sending, finished }

    private var targets: [Instance] { store.instances.filter { $0.id != source.instance.id } }

    /// The one printer chosen, when it's free to start a print.
    private var printTarget: PrinterSession? {
        guard chosen.count == 1, let id = chosen.first, let session = store.sessions[id], session.canControl else { return nil }
        return session
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send to another printer")
                .font(Typeface.title).foregroundStyle(Palette.paper)
            FileSummaryCard(file: file, client: source.client, tint: filament)

            if targets.isEmpty {
                Text("Add another printer first, then you can send files between them.")
                    .font(Typeface.body).foregroundStyle(Palette.dust)
            } else {
                (phase == .choosing ? Text("Choose one or more printers. The file goes to the top level of their files.") : Text(verbatim: statusLine))
                    .font(Typeface.body).foregroundStyle(Palette.dust)
                VStack(spacing: 8) {
                    ForEach(targets) { instance in row(instance) }
                }
                if phase == .choosing {
                    Toggle(isOn: Binding(get: { printNow && printTarget != nil }, set: { printNow = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start printing straight away").font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                            Text(printTarget == nil ? "Choose a single printer that's ready to print." : "Make sure its bed is clear first.")
                                .font(Typeface.caption).foregroundStyle(Palette.faint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                    .tint(Palette.accent)
                    .disabled(printTarget == nil)
                }
            }

            HStack {
                Spacer()
                if phase == .finished {
                    Button("Done") { dismiss() }.buttonStyle(.plate).keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { work?.cancel(); dismiss() }.buttonStyle(.plateQuiet).keyboardShortcut(.cancelAction)
                    Button(printNow && printTarget != nil ? "Send and print" : "Send", action: send)
                        .buttonStyle(.plate)
                        .keyboardShortcut(.defaultAction)
                        .disabled(chosen.isEmpty || phase != .choosing)
                }
            }
        }
        .padding(26)
        .frame(width: 500)
        .background(Palette.extrusion)
        .animation(.easeOut(duration: 0.2), value: phase)
    }

    private var statusLine: String {
        switch phase {
        case .choosing: ""
        case .fetching: String(localized: "Fetching the file from \(source.instance.name)…")
        case .sending: String(localized: "Sending…")
        case .finished: failures.isEmpty ? String(localized: "Sent.") : String(localized: "Some printers didn't get the file.")
        }
    }

    private func row(_ instance: Instance) -> some View {
        let session = store.sessions[instance.id]
        let online = session?.link == .online
        let selected = chosen.contains(instance.id)
        return Button {
            if selected { chosen.remove(instance.id) } else { chosen.insert(instance.id) }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(store.filament(for: instance)).frame(width: 4, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.name).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                    if let failure = failures[instance.id] {
                        Text(failure).font(Typeface.caption).foregroundStyle(Palette.hot).lineLimit(2)
                    } else {
                        Text(session?.stateText ?? "").font(Typeface.caption).foregroundStyle(Palette.faint)
                    }
                }
                Spacer()
                trailing(for: instance.id, selected: selected, online: online)
            }
            .padding(12)
            .machined(radius: 12, fill: selected && phase == .choosing ? Palette.extrusionHi : Palette.graphite)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Palette.accent.opacity(0.7) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!online || phase != .choosing)
        .opacity(online || selected ? 1 : 0.5)
    }

    @ViewBuilder private func trailing(for id: UUID, selected: Bool, online: Bool) -> some View {
        if phase == .choosing || !selected {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(selected ? Palette.accent : Palette.faint)
        } else if failures[id] != nil {
            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.hot)
        } else if let fraction = progress[id], fraction >= 1 {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.ready)
        } else if let fraction = progress[id] {
            ProgressView(value: fraction).progressViewStyle(.linear).tint(Palette.accent).frame(width: 90)
        } else {
            ProgressView().controlSize(.small).tint(Palette.accent)
        }
    }

    private func send() {
        let destinations = targets.filter { chosen.contains($0.id) }.compactMap { store.sessions[$0.id] }
        let startPrint = printNow && printTarget != nil
        phase = .fetching
        work = Task {
            let data: Data
            do {
                data = try await source.client.download(file)
            } catch {
                for session in destinations { failures[session.instance.id] = "Couldn't fetch the file: \(error.localizedDescription)" }
                phase = .finished
                return
            }
            phase = .sending
            await withTaskGroup(of: Void.self) { group in
                for session in destinations {
                    let id = session.instance.id
                    let client = session.client
                    let name = file.name
                    group.addTask {
                        do {
                            try await client.upload(data: data, filename: name, select: startPrint, print: startPrint) { fraction in
                                Task { @MainActor in progress[id] = min(fraction, 0.99) }
                            }
                            await MainActor.run { progress[id] = 1 }
                            await session.refreshFiles()
                        } catch {
                            await MainActor.run { failures[id] = error.localizedDescription }
                        }
                    }
                }
            }
            phase = .finished
        }
    }
}
