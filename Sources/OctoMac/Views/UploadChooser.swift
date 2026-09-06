import OctoPrintKit
import SwiftUI

/// Asks which printer should receive files opened from Finder.
struct UploadChooser: View {
    @Environment(InstanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let files: [URL]
    let chose: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(files.count == 1 ? "Upload \(files[0].lastPathComponent)?" : "Upload \(files.count) files?")
                .font(Typeface.title).foregroundStyle(Palette.paper)
                .lineLimit(2)
            Text("Choose a printer. The file\(files.count == 1 ? " goes" : "s go") to its OctoPrint, ready to print.")
                .font(Typeface.body).foregroundStyle(Palette.dust)
            VStack(spacing: 8) {
                ForEach(store.instances) { instance in
                    let session = store.sessions[instance.id]
                    let online = session?.link == .online
                    Button {
                        chose(instance.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 2).fill(store.filament(for: instance)).frame(width: 4, height: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(instance.name).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                                Text(session?.stateText ?? "").font(Typeface.caption).foregroundStyle(Palette.faint)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.circle.fill").foregroundStyle(online ? Palette.accent : Palette.faint)
                        }
                        .padding(12)
                        .machined(radius: 12)
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
            }
        }
        .padding(26)
        .frame(width: 460)
        .background(Palette.extrusion)
    }
}
