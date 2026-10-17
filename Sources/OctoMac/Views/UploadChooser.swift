import OctoPrintKit
import SwiftUI

/// Asks which printers should receive files opened from Finder. One or several.
struct UploadChooser: View {
    @Environment(InstanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let files: [URL]
    let chose: ([UUID]) -> Void
    @State private var chosen: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(files.count == 1 ? "Upload \(files[0].lastPathComponent)?" : "Upload \(files.count) files?")
                .font(Typeface.title).foregroundStyle(Palette.paper)
                .lineLimit(2)
            Text("Choose one or more printers. The file\(files.count == 1 ? " goes" : "s go") to each one's OctoPrint, ready to print.")
                .font(Typeface.body).foregroundStyle(Palette.dust)
            VStack(spacing: 8) {
                ForEach(store.instances) { instance in
                    let session = store.sessions[instance.id]
                    let online = session?.link == .online
                    let selected = chosen.contains(instance.id)
                    Button {
                        if selected { chosen.remove(instance.id) } else { chosen.insert(instance.id) }
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 2).fill(store.filament(for: instance)).frame(width: 4, height: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(instance.name).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                                Text(session?.stateText ?? "").font(Typeface.caption).foregroundStyle(Palette.faint)
                            }
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(selected ? Palette.accent : Palette.faint)
                        }
                        .padding(12)
                        .machined(radius: 12, fill: selected ? Palette.extrusionHi : Palette.graphite)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? Palette.accent.opacity(0.7) : .clear, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!online)
                    .opacity(online ? 1 : 0.5)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plateQuiet).keyboardShortcut(.cancelAction)
                Button("Upload") {
                    chose(store.instances.map(\.id).filter(chosen.contains))
                    dismiss()
                }
                .buttonStyle(.plate)
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(26)
        .frame(width: 460)
        .onAppear {
            // With only one printer online, it's already chosen.
            let online = store.instances.filter { store.sessions[$0.id]?.link == .online }
            if online.count == 1 { chosen = [online[0].id] }
        }
        .background(Palette.extrusion)
    }
}
