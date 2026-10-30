import AppKit
import OctoPrintKit
import SwiftUI

/// Power and temperature health of the Raspberry Pi running OctoPrint (from the Pi Support plugin).
struct PiHealthPanel: View {
    let session: PrinterSession
    let pi: PiSupportInfo

    var body: some View {
        StagePanel(title: "Raspberry Pi", verbatimDetail: pi.octoPiVersion.map { "OctoPi \($0)" }) {
            VStack(alignment: .leading, spacing: 14) {
                if let model = pi.model {
                    Text(verbatim: model).font(Typeface.subhead).foregroundStyle(Palette.paper)
                }
                if let throttle = session.throttle {
                    row("Power", symbol: "bolt.fill",
                        now: throttle.currentUndervoltage, earlier: throttle.pastUndervoltage,
                        good: "Steady", bad: "Too low right now", past: "Dipped since the Pi started",
                        advice: "Low power makes the Pi slow down. A better power supply or cable usually fixes it.")
                    row("Temperature", symbol: "thermometer.medium",
                        now: throttle.currentOverheat, earlier: throttle.pastOverheat,
                        good: "Cool enough", bad: "Too hot right now", past: "Got too hot since the Pi started",
                        advice: "A hot Pi slows down. A small heatsink or fan helps.")
                    row("Speed", symbol: "speedometer",
                        now: throttle.currentIssue && !throttle.currentUndervoltage && !throttle.currentOverheat,
                        earlier: throttle.pastIssue && !throttle.pastUndervoltage && !throttle.pastOverheat,
                        good: "Full speed", bad: "Slowed down right now", past: "Slowed down since the Pi started",
                        advice: "The Pi has been running below full speed, which can make prints stutter.")
                } else {
                    Text("This Pi doesn't report its power and temperature.").font(Typeface.body).foregroundStyle(Palette.dust)
                }
            }
        }
    }

    private func row(_ title: LocalizedStringKey, symbol: String, now: Bool, earlier: Bool,
                     good: LocalizedStringKey, bad: LocalizedStringKey, past: LocalizedStringKey, advice: LocalizedStringKey) -> some View {
        let color = now ? Palette.hot : earlier ? Palette.warm : Palette.ready
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(Circle().fill(color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typeface.caption).foregroundStyle(Palette.faint)
                Text(now ? bad : earlier ? past : good).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                if now || earlier {
                    Text(advice).font(Typeface.caption).foregroundStyle(Palette.dust)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// What the Software Update plugin says about OctoPrint and its plugins.
struct UpdatesPanel: View {
    let session: PrinterSession
    let updates: [SoftwareComponent]
    @State private var checking = false
    @State private var showAll = false
    @State private var confirmingUpdate = false
    @State private var showingLog = true

    private var pending: [SoftwareComponent] { updates.filter(\.updateAvailable) }

    var body: some View {
        StagePanel(title: "Software", detail: pending.isEmpty ? "Up to date" : "\(pending.count) updates") {
            VStack(alignment: .leading, spacing: 12) {
                if pending.isEmpty {
                    Label("OctoPrint and its \(updates.count - 1) plugins are up to date.", systemImage: "checkmark.circle.fill")
                        .font(Typeface.bodyStrong).foregroundStyle(Palette.ready)
                } else {
                    ForEach(pending) { component in
                        HStack {
                            Text(verbatim: component.name).font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(1)
                            Spacer()
                            Text("\(component.installed) → \(component.available ?? "?")")
                                .font(Typeface.number(13)).foregroundStyle(Palette.warm)
                        }
                    }
                    Text("Updating restarts OctoPrint, so wait until nothing is printing.")
                        .font(Typeface.caption).foregroundStyle(Palette.faint)
                }

                if session.updatingSince != nil || !session.updateLog.isEmpty {
                    DisclosureGroup(isExpanded: $showingLog) {
                        LiveLog(lines: session.updateLog).frame(height: 180).padding(.top, 6)
                    } label: {
                        HStack(spacing: 8) {
                            if session.updatingSince != nil { ProgressView().controlSize(.small).tint(Palette.accent) }
                            Text(session.updatingSince != nil ? "Updating. OctoPrint restarts when it's done." : "The last update's log")
                                .font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                        }
                    }
                    .tint(Palette.dust)
                }

                if showAll {
                    VStack(spacing: 6) {
                        ForEach(updates.filter { !$0.updateAvailable }) { component in
                            HStack {
                                Text(verbatim: component.name).font(Typeface.body).foregroundStyle(Palette.dust).lineLimit(1)
                                Spacer()
                                Text(verbatim: component.installed).font(Typeface.number(12)).foregroundStyle(Palette.faint)
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                HStack(spacing: 8) {
                    Button(showAll ? "Hide versions" : "Show versions") { withAnimation(.snappy) { showAll.toggle() } }
                        .buttonStyle(.plateQuiet)
                    Spacer()
                    Button {
                        checking = true
                        Task {
                            await session.refreshUpdates(force: true)
                            checking = false
                        }
                    } label: {
                        if checking { ProgressView().controlSize(.small) } else { Text("Check now") }
                    }
                    .buttonStyle(.plateQuiet)
                    .disabled(checking)
                    if !pending.isEmpty {
                        Button { confirmingUpdate = true } label: {
                            Label(pending.count == 1 ? "Update" : "Update all", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.plate)
                        .disabled(session.flags.isJobActive || session.updatingSince != nil || !pending.allSatisfy(\.updatePossible))
                        .help(session.flags.isJobActive ? "Wait until the print finishes" : "Install the updates; OctoPrint restarts afterwards")
                    }
                }
                .controlSize(.small)
            }
        }
        .sheet(isPresented: $confirmingUpdate) {
            ConfirmSheet(symbol: "arrow.down.circle", tint: Palette.warm, title: pending.count == 1 ? "Update \(pending[0].name)?" : "Install \(pending.count) updates?",
                         message: "OctoPrint downloads the updates, installs them and restarts. The printer stays connected, but OctoMac loses touch with it for a minute or two.",
                         confirmTitle: "Update", onConfirm: { session.updateSoftware(pending.map(\.id)) })
        }
    }
}

/// OctoPrint's log files: view the latest part, or save the whole file.
struct LogsPanel: View {
    let session: PrinterSession
    @State private var viewing: LogFile?
    @State private var deleting: LogFile?

    var body: some View {
        StagePanel(title: "Logs", detail: session.logs.isEmpty ? nil : "\(session.logs.count) files") {
            if session.logs.isEmpty {
                Text("No log files, or this account can't read them.").font(Typeface.body).foregroundStyle(Palette.dust)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(session.logs) { file in
                            LogRow(file: file) { viewing = file } save: { save(file) } delete: { deleting = file }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .sheet(item: $viewing) { file in
            LogViewer(session: session, file: file)
        }
        .sheet(item: $deleting) { file in
            ConfirmSheet(symbol: "trash", title: "Delete this log?", message: "OctoPrint removes it from the Raspberry Pi. Logs are useful when reporting a problem, so keep recent ones.",
                         confirmTitle: "Delete", onConfirm: { session.deleteLog(file) }) {
                Text(verbatim: file.name).font(Typeface.caption).foregroundStyle(Palette.faint)
            }
        }
    }

    private func save(_ file: LogFile) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if let data = await session.logContents(file) { try? data.write(to: url) }
        }
    }
}

private struct LogRow: View {
    let file: LogFile
    let view: () -> Void
    let save: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.plaintext").foregroundStyle(Palette.dust).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(1).truncationMode(.middle)
                Text([file.size.map(Fmt.bytes), file.date.map { Date(timeIntervalSince1970: $0).formatted(.relative(presentation: .named)) }]
                        .compactMap { $0 }.joined(separator: ", "))
                    .font(Typeface.caption).foregroundStyle(Palette.faint)
            }
            Spacer()
            Button("View", action: view).buttonStyle(.plateQuiet).controlSize(.small).disabled((file.size ?? 0) == 0)
            Button { save() } label: { Image(systemName: "square.and.arrow.down") }
                .buttonStyle(.plateQuiet).controlSize(.small)
                .help("Save the whole log")
            Button { delete() } label: { Image(systemName: "trash") }
                .buttonStyle(.plateQuiet).controlSize(.small)
                .help("Delete this log")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Palette.extrusionHi : .clear))
        .onHover { hovering = $0 }
    }
}

/// Shows the end of a log file, newest lines at the bottom.
struct LogViewer: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    let file: LogFile
    @State private var text: String?

    /// Logs can be many megabytes; the most recent part is what matters.
    private static let tail = 400_000

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(file.name).font(Typeface.title).foregroundStyle(Palette.paper)
                Spacer()
                if let text {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.plateQuiet)
                }
                Button("Done") { dismiss() }.buttonStyle(.plate).keyboardShortcut(.defaultAction)
            }
            if (file.size ?? 0) > Self.tail {
                Text("Showing the most recent \(Fmt.bytes(Self.tail)) of \(Fmt.bytes(file.size ?? 0)).")
                    .font(Typeface.caption).foregroundStyle(Palette.faint)
            }
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    (text.map { Text(verbatim: $0) } ?? Text("Loading…"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.dust)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                    Color.clear.frame(height: 1).id("end")
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.graphite))
                .onChange(of: text) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .padding(24)
        .frame(width: 900, height: 620)
        .background(Palette.extrusion)
        .task {
            guard let data = await session.logContents(file) else { text = String(localized: "Couldn't load this log."); return }
            text = String(decoding: data.suffix(Self.tail), as: UTF8.self)
        }
    }
}
