import AVKit
import OctoPrintKit
import SwiftUI

/// The History tab: statistics, what's been printed lately, and OctoPrint's timelapse videos.
struct HistoryPage: View {
    let session: PrinterSession
    let filament: Color
    let openFile: () -> Void

    var body: some View {
        GeometryReader { geo in
            Group {
                if geo.size.width >= 940 && geo.size.height >= 560 {
                    VStack(spacing: 20) {
                        StatisticsPanel(session: session, filament: filament)
                        HStack(alignment: .top, spacing: 20) {
                            RecentPrintsPanel(session: session, filament: filament, openFile: openFile)
                            TimelapsePanel(session: session, filament: filament)
                        }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            StatisticsPanel(session: session, filament: filament)
                            RecentPrintsPanel(session: session, filament: filament, openFile: openFile).frame(height: 420)
                            TimelapsePanel(session: session, filament: filament).frame(height: 420)
                        }
                    }
                }
            }
        }
        // Again once the printer is online, in case the tab opened before OctoMac had connected.
        .task(id: "\(session.instance.id)-\(session.link == .online)") {
            if session.link == .online { await session.refreshTimelapses() }
        }
    }
}

private struct RecentPrintsPanel: View {
    let session: PrinterSession
    let filament: Color
    let openFile: () -> Void

    var body: some View {
        let prints = session.recentPrints
        StagePanel(title: "Recent prints", detail: prints.isEmpty ? nil : "\(prints.count) files", fills: true) {
            if prints.isEmpty {
                Text("Nothing printed yet. Prints from OctoPrint's own file list show up here, newest first.")
                    .font(Typeface.body).foregroundStyle(Palette.dust)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(prints) { file in
                            RecentPrintRow(session: session, file: file, filament: filament, openFile: openFile)
                        }
                    }
                }
            }
        }
    }
}

private struct RecentPrintRow: View {
    let session: PrinterSession
    let file: FileEntry
    let filament: Color
    let openFile: () -> Void
    @State private var hovering = false
    @State private var editingNote = false

    var body: some View {
        let name = SlicedName(file.displayName)
        let last = file.prints?.last
        let note = session.note(for: file.path)
        HStack(spacing: 14) {
            FileThumbnail(file: file, client: session.client, tint: filament, radius: 8)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(verbatim: name.title).font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(1)
                    if let rating = note?.rating {
                        StarRating(rating: .constant(rating), size: 9, editable: false).fixedSize()
                    }
                }
                HStack(spacing: 10) {
                    if let success = last?.success {
                        Label(success ? "Finished" : "Didn't finish", systemImage: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(success ? Palette.ready : Palette.hot)
                    }
                    if let date = last?.date {
                        Text(Date(timeIntervalSince1970: date).formatted(.relative(presentation: .named)))
                    }
                    if let time = last?.printTime { Text(Fmt.duration(time)) }
                }
                .font(Typeface.caption).foregroundStyle(Palette.faint)
                .lineLimit(1)
                if let text = note?.text, !text.isEmpty {
                    Text(verbatim: text).font(Typeface.caption).foregroundStyle(Palette.dust).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button { editingNote = true } label: {
                Image(systemName: note == nil ? "star" : "note.text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(note == nil ? Palette.faint : Palette.dust)
                    .opacity(hovering || note != nil ? 1 : 0)
            }
            .buttonStyle(.plain)
            .help("Rate this print, or add a note for next time")
            .popover(isPresented: $editingNote, arrowEdge: .bottom) {
                NoteEditor(session: session, path: file.path, title: name.title)
            }
            if let prints = file.prints {
                Text("\(prints.success ?? 0) of \((prints.success ?? 0) + (prints.failure ?? 0)) finished")
                    .font(Typeface.number(12)).foregroundStyle(Palette.faint)
                    .lineLimit(1)
                    .help("How many of this file's prints finished")
            }
            Button("Open") {
                session.select(file, print: false)
                openFile()
            }
            .buttonStyle(.plateQuiet)
            .controlSize(.small)
            .disabled(!session.canControl)
            .help(session.controlBlocker ?? String(localized: "Open this file, ready to print again"))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Palette.extrusionHi : .clear))
        .onHover { hovering = $0 }
    }
}

private struct TimelapsePanel: View {
    let session: PrinterSession
    let filament: Color
    @State private var playing: TimelapseFile?
    @State private var deleting: TimelapseFile?
    @State private var editing = false

    var body: some View {
        let list = session.timelapses
        let files = list?.files ?? []
        let unrendered = list?.unrendered ?? []
        StagePanel(title: "Timelapses", detail: list.map { timelapseMode($0) }, fills: true) {
            VStack(alignment: .leading, spacing: 12) {
                if files.isEmpty && unrendered.isEmpty {
                    Text(list?.config?["type"]?.stringValue == "off"
                         ? "Timelapses are switched off. Turn them on in Timelapse settings and each print gets a video here."
                         : "No timelapses yet. They appear here once a print with timelapse turned on finishes.")
                        .font(Typeface.body).foregroundStyle(Palette.dust)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(files) { file in
                                TimelapseRow(session: session, file: file, rendered: true) { playing = file } delete: { deleting = file }
                            }
                            if !unrendered.isEmpty {
                                Text("Waiting to be made into videos")
                                    .font(Typeface.caption).foregroundStyle(Palette.faint)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 10)
                                ForEach(unrendered) { file in
                                    TimelapseRow(session: session, file: file, rendered: false) {} delete: { deleting = file }
                                }
                            }
                        }
                    }
                }
                if list != nil {
                    HStack {
                        Spacer()
                        Button { editing = true } label: { Label("Timelapse settings…", systemImage: "slider.horizontal.3") }
                            .buttonStyle(.plateQuiet)
                            .controlSize(.small)
                            .help("Choose when OctoPrint takes pictures and how the video is made")
                    }
                }
            }
        }
        .sheet(isPresented: $editing) { TimelapseSettingsSheet(session: session) }
        .sheet(item: $playing) { TimelapsePlayer(session: session, file: $0) }
        .sheet(item: $deleting) { file in
            // Pictures still waiting to be made into a video live somewhere else in OctoPrint.
            if session.timelapses?.unrendered?.contains(where: { $0.name == file.name }) == true {
                ConfirmSheet(symbol: "trash", title: "Delete these pictures?", message: "The pictures for \(file.name) are deleted from OctoPrint, so no video can be made from them. This can't be undone.",
                             confirmTitle: "Delete", onConfirm: { session.deleteUnrenderedTimelapse(file) })
            } else {
                ConfirmSheet(symbol: "trash", title: "Delete this timelapse?", message: "\(file.name) is deleted from OctoPrint. This can't be undone.",
                             confirmTitle: "Delete", onConfirm: { session.deleteTimelapse(file) })
            }
        }
    }

    private func timelapseMode(_ list: TimelapseList) -> LocalizedStringKey {
        switch list.config?["type"]?.stringValue {
        case "off": "Off"
        case "zchange": "On layer change"
        case "timed": "Timed"
        default: ""
        }
    }
}

private struct TimelapseRow: View {
    let session: PrinterSession
    let file: TimelapseFile
    let rendered: Bool
    let play: () -> Void
    let delete: () -> Void
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.graphite)
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: rendered ? "film" : "photo.stack").foregroundStyle(Palette.faint)
                }
            }
            .frame(width: 80, height: 45)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: file.name).font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(1).truncationMode(.middle)
                Text([file.date, file.size].compactMap { $0 }.joined(separator: ", "))
                    .font(Typeface.caption).foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer(minLength: 8)
            if rendered {
                Button { play() } label: { Label("Play", systemImage: "play.fill") }
                    .buttonStyle(.plate).controlSize(.small)
                Button { save() } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(.plateQuiet).controlSize(.small).help("Save the video")
            } else {
                Button("Make video") { session.renderTimelapse(file) }
                    .buttonStyle(.plateQuiet).controlSize(.small)
                    .help("Ask OctoPrint to turn these snapshots into a video")
            }
            Button(action: delete) { Image(systemName: "trash") }
                .buttonStyle(.plateQuiet).controlSize(.small).help("Delete")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Palette.extrusionHi : .clear))
        .onHover { hovering = $0 }
        .task {
            if let path = file.thumbnail, let url = session.client.resolve(path) {
                thumbnail = await ThumbnailStore.shared.image(for: url, client: session.client)
            }
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if let data = await session.timelapseData(file) { try? data.write(to: url) }
        }
    }
}

/// Downloads a timelapse (OctoPrint wants the API key, so it can't simply be streamed) and plays it.
private struct TimelapsePlayer: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    let file: TimelapseFile
    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(verbatim: file.name).font(Typeface.subhead).foregroundStyle(Palette.paper).lineLimit(1)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.plate).keyboardShortcut(.defaultAction)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black)
                if let player {
                    VideoPlayer(player: player).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if failed {
                    Text("Couldn't download this video.").font(Typeface.body).foregroundStyle(Palette.dust)
                } else {
                    VStack(spacing: 10) {
                        ProgressView().tint(Palette.accent)
                        Text(file.size.map { "Downloading \($0)…" } ?? "Downloading the video…").font(Typeface.caption).foregroundStyle(Palette.faint)
                    }
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
        }
        .padding(22)
        .frame(width: 860)
        .background(Palette.extrusion)
        .task {
            guard let data = await session.timelapseData(file) else { failed = true; return }
            let url = FileManager.default.temporaryDirectory.appending(path: "OctoMac-\(UUID().uuidString)-\(file.name)")
            do {
                try data.write(to: url)
                let player = AVPlayer(url: url)
                self.player = player
                player.play()
            } catch {
                failed = true
            }
        }
        .onDisappear { player?.pause() }
    }
}
