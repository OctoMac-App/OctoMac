import OctoPrintKit
import SwiftUI
import UniformTypeIdentifiers

/// OctoPrint's backups (Backup & Restore plugin): make one, save it to this Mac, or delete old ones. Restoring is
/// left to OctoPrint's own page, which asks for the password again and restarts.
struct BackupsPanel: View {
    let session: PrinterSession
    let state: Backup.State
    @State private var choosing = false
    @State private var deleting: Backup.File?
    /// Which five to show, newest first. Some people keep dozens.
    @State private var page = 0

    private static let perPage = 5
    private var pageCount: Int { max(1, (state.backups.count + Self.perPage - 1) / Self.perPage) }
    private var shown: ArraySlice<Backup.File> {
        let start = min(page, pageCount - 1) * Self.perPage
        return state.backups[start..<min(start + Self.perPage, state.backups.count)]
    }

    var body: some View {
        StagePanel(title: "Backups", detail: state.backups.isEmpty ? nil : "\(state.backups.count) on the Raspberry Pi") {
            VStack(alignment: .leading, spacing: 12) {
                if state.inProgress {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(Palette.accent)
                        Text("Making a backup. This can take a few minutes.")
                            .font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                    }
                }

                if state.backups.isEmpty {
                    Text("No backups yet. A backup keeps OctoPrint's settings, plugins and files, so you can set it up again quickly if the SD card fails.")
                        .font(Typeface.body).foregroundStyle(Palette.dust)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 4) {
                        ForEach(shown) { file in
                            BackupRow(session: session, file: file, isNew: file.name == session.newBackup,
                                      save: { save(file) }, delete: { deleting = file })
                        }
                    }
                    if pageCount > 1 { pager }
                }

                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(URL(string: "#settings_plugin_backup", relativeTo: session.instance.baseURL)?.absoluteURL
                                                ?? session.instance.baseURL)
                    } label: {
                        Label("Restore in OctoPrint", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.plateQuiet)
                    .help("Restoring replaces OctoPrint's settings and restarts it, so it's done on OctoPrint's own page")
                    Spacer()
                    Button { choosing = true } label: {
                        Label("Back up now…", systemImage: "externaldrive.badge.plus")
                    }
                    .buttonStyle(.plate)
                    .disabled(state.inProgress || session.flags.isJobActive)
                    .help(session.flags.isJobActive ? "Wait until the print finishes" : "Make a backup on the Raspberry Pi")
                }
                .controlSize(.small)
            }
        }
        // A new backup goes to the top, so show it.
        .onChange(of: session.newBackup) { page = 0 }
        .onChange(of: pageCount) { page = min(page, pageCount - 1) }
        .sheet(isPresented: $choosing) { BackupOptionsSheet(session: session) }
        .sheet(item: $deleting) { file in
            ConfirmSheet(symbol: "trash", title: "Delete this backup?",
                         message: "OctoPrint removes it from the Raspberry Pi. Copies you've saved to this Mac aren't affected.",
                         confirmTitle: "Delete", onConfirm: { session.deleteBackup(file) }) {
                Text(verbatim: file.name).font(Typeface.caption).foregroundStyle(Palette.faint)
            }
        }
    }

    private var pager: some View {
        HStack(spacing: 6) {
            Spacer()
            Button { withAnimation(.snappy) { page -= 1 } } label: { Image(systemName: "chevron.left") }
                .disabled(page == 0)
                .help("Newer backups")
                .accessibilityLabel("Newer backups")
            Text("Page \(min(page, pageCount - 1) + 1) of \(pageCount)")
                .font(Typeface.caption).foregroundStyle(Palette.faint)
                .monospacedDigit()
                .frame(minWidth: 80)
            Button { withAnimation(.snappy) { page += 1 } } label: { Image(systemName: "chevron.right") }
                .disabled(page >= pageCount - 1)
                .help("Older backups")
                .accessibilityLabel("Older backups")
            Spacer()
        }
        .buttonStyle(.plateQuiet)
        .controlSize(.small)
    }

    private func save(_ file: Backup.File) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        session.downloadBackup(file, to: url)
    }
}

private struct BackupRow: View {
    let session: PrinterSession
    let file: Backup.File
    let isNew: Bool
    let save: () -> Void
    let delete: @MainActor () -> Void
    @State private var hovering = false

    private var saving: Double? { session.backupDownload?.name == file.name ? session.backupDownload?.fraction : nil }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox").foregroundStyle(isNew ? Palette.accent : Palette.dust).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(file.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? file.name)
                        .font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(1)
                    if isNew { Text("New").font(Typeface.caption).foregroundStyle(Palette.accent) }
                }
                Text([Fmt.bytes(Int(file.size)), file.date.map { $0.formatted(.relative(presentation: .named)) }].compactMap { $0 }.joined(separator: ", "))
                    .font(Typeface.caption).foregroundStyle(Palette.faint)
            }
            Spacer()
            if let saving {
                ProgressView(value: saving).progressViewStyle(.linear).tint(Palette.accent).frame(width: 90)
            } else {
                Button { save() } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(.plateQuiet).controlSize(.small)
                    .disabled(session.backupDownload != nil)
                    .help("Save to this Mac")
                AppMenu(items: [.action(String(localized: "Delete…"), symbol: "trash", destructive: true, run: delete)], width: 180) {
                    QuietMenuLabel(symbol: "ellipsis")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Palette.extrusionHi : .clear))
        .onHover { hovering = $0 }
        .help(file.name)
    }
}

/// What to put in a new backup. Settings and plugins always go in; uploads and timelapses can be large.
private struct BackupOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    @AppStorage("backup.includeUploads") private var includeUploads = true
    @AppStorage("backup.includeTimelapses") private var includeTimelapses = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Back up OctoPrint").font(Typeface.title).foregroundStyle(Palette.paper)
                Text("OctoPrint makes the backup on the Raspberry Pi, with its settings and plugins. You can save a copy to this Mac once it's done.")
                    .font(Typeface.body).foregroundStyle(Palette.dust)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 10) {
                option("Include uploaded files", detail: "Your G-code files. Leave them out for a much smaller backup.", isOn: $includeUploads)
                option("Include timelapses", detail: "Timelapse videos can take up a lot of space.", isOn: $includeTimelapses)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plateQuiet).keyboardShortcut(.cancelAction)
                Button("Back up") {
                    var leaveOut: [Backup.Part] = []
                    if !includeUploads { leaveOut.append(.uploads) }
                    if !includeTimelapses { leaveOut.append(.timelapse) }
                    session.createBackup(excluding: leaveOut)
                    dismiss()
                }
                .buttonStyle(.plate)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 460)
        .background(Palette.extrusion)
    }

    private func option(_ title: LocalizedStringKey, detail: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                Text(detail).font(Typeface.caption).foregroundStyle(Palette.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(Palette.accent)
        .padding(12)
        .machined(radius: 12, fill: Palette.graphite)
    }
}
