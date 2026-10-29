import SwiftUI

/// The files lined up to print next on this printer. When a print finishes, OctoMac asks you to clear the bed and
/// start the next one; nothing starts on its own.
struct QueuePanel: View {
    let session: PrinterSession
    let filament: Color
    @State private var startingNext = false

    var body: some View {
        let queue = session.journal.queue
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Up next").font(Typeface.subhead).foregroundStyle(Palette.paper)
                Text(queue.count == 1 ? "1 file" : "\(queue.count) files").font(Typeface.caption).foregroundStyle(Palette.faint)
                Spacer()
                Button { startingNext = true } label: { Label("Start next", systemImage: "play.fill") }
                    .buttonStyle(.plate(filament))
                    .controlSize(.small)
                    .disabled(!session.canControl)
                    .help(session.controlBlocker ?? "Start the first file in the queue")
            }
            VStack(spacing: 0) {
                ForEach(Array(queue.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Text(verbatim: "\(index + 1)").font(Typeface.number(14)).foregroundStyle(Palette.faint).frame(width: 20)
                        Text(item.name).font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(1)
                        Spacer(minLength: 8)
                        Button { session.moveInQueue(item.id, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.plain).foregroundStyle(Palette.dust).disabled(index == 0).help("Move up")
                        Button { session.moveInQueue(item.id, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.plain).foregroundStyle(Palette.dust).disabled(index == queue.count - 1).help("Move down")
                        Button { session.removeFromQueue(item.id) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(Palette.faint).help("Take out of the queue")
                    }
                    .padding(.vertical, 8)
                    if index < queue.count - 1 { Divider().overlay(Palette.edge) }
                }
            }
            .padding(.horizontal, 12)
            .machined(radius: 12, fill: Palette.graphite)
            Text("When a print finishes, OctoMac asks you to clear the bed before starting the next one.")
                .font(Typeface.caption).foregroundStyle(Palette.faint)
        }
        .padding(16)
        .machined(radius: 16)
        .sheet(isPresented: $startingNext) {
            ConfirmSheet(symbol: "list.number", title: queue.first.map { "Start \($0.name)?" } ?? "Start the next print?",
                         message: "Make sure the bed is clear first. The printer starts straight away.",
                         confirmTitle: "Start print", onConfirm: { session.startNextInQueue() })
        }
    }
}
