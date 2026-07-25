import OctoPrintKit
import SwiftUI

/// A confirmation in the app's own style, shown as a sheet: icon, title, optional detail (e.g. the file in question),
/// an explanation, and Cancel / confirm buttons. Cancel is the default for Esc.
struct ConfirmSheet<Detail: View>: View {
    let symbol: String
    var tint: Color = Palette.hot
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    @ViewBuilder var detail: Detail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(tint.opacity(0.15)))
                Text(title).font(Typeface.title).foregroundStyle(Palette.paper)
            }
            detail
            Text(message)
                .font(Typeface.body)
                .foregroundStyle(Palette.dust)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plateQuiet)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.plate(tint))
            }
        }
        .padding(26)
        .frame(width: 480)
        .background(Palette.extrusion)
    }
}

extension ConfirmSheet where Detail == EmptyView {
    init(symbol: String, tint: Color = Palette.hot, title: String, message: String, confirmTitle: String, onConfirm: @escaping () -> Void) {
        self.init(symbol: symbol, tint: tint, title: title, message: message, confirmTitle: confirmTitle, onConfirm: onConfirm) { EmptyView() }
    }
}

/// The file or folder a confirmation is about, shown as a small card.
struct FileSummaryCard: View {
    let file: FileEntry
    let client: OctoPrintClient
    var tint: Color = Palette.accent

    var body: some View {
        HStack(spacing: 14) {
            FileThumbnail(file: file, client: client, tint: tint, radius: 10)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.isFolder ? file.displayName : SlicedName(file.displayName).title)
                    .font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(2)
                Text(file.isFolder ? folderSummary : file.name)
                    .font(Typeface.caption).foregroundStyle(Palette.faint)
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                if !file.isFolder, let size = file.size {
                    Text(Fmt.bytes(size)).font(Typeface.number(12)).foregroundStyle(Palette.dust)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .machined(radius: 12, fill: Palette.graphite)
    }

    private var folderSummary: String {
        let count = file.children?.count ?? 0
        return count == 1 ? "1 item" : "\(count) items"
    }
}

/// Asks for a name (e.g. a new folder), in the app's style.
struct NameSheet: View {
    let title: String
    let placeholder: String
    let confirmTitle: String
    let onConfirm: (String) -> Void
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Palette.accent.opacity(0.15)))
                Text(title).font(Typeface.title).foregroundStyle(Palette.paper)
            }
            TextField("", text: $name, prompt: Text(placeholder).foregroundStyle(Palette.faint))
                .plateField()
                .onSubmit(confirm)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plateQuiet)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: confirm)
                    .buttonStyle(.plate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(26)
        .frame(width: 440)
        .background(Palette.extrusion)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    private func confirm() {
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed)
        dismiss()
    }
}
