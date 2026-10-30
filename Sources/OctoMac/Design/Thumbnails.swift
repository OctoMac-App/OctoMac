import AppKit
import OctoPrintKit
import SwiftUI
import UniformTypeIdentifiers

/// Fetches and caches thumbnail-plugin images. They sit behind OctoPrint's auth, so `AsyncImage` can't load them.
@MainActor
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private let cache = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    func cached(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    func image(for url: URL, client: OctoPrintClient) async -> NSImage? {
        if let image = cached(url) { return image }
        if let task = inFlight[url] { return await task.value }
        let task = Task<NSImage?, Never> {
            var request = URLRequest(url: url)
            client.authorize(&request)
            guard let (data, _) = try? await client.send(request) else { return nil }
            return NSImage(data: data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

/// A file's preview: the plugin thumbnail when there is one, otherwise a filament-tinted glyph.
struct FileThumbnail: View {
    let file: FileEntry?
    let client: OctoPrintClient
    var tint: Color = Palette.accent
    var radius: CGFloat = 10
    @State private var image: NSImage?

    private var url: URL? { file?.thumbnail.flatMap(client.resolve) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(RadialGradient(colors: [Palette.extrusionHi, Palette.graphite], center: .center, startRadius: 0, endRadius: 80))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: glyph)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(glyphTint)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.05), lineWidth: 1))
        .task(id: url) {
            guard let url else { image = nil; return }
            image = ThumbnailStore.shared.cached(url)
            if image == nil { image = await ThumbnailStore.shared.image(for: url, client: client) }
        }
    }

    private var glyph: String {
        guard let file else { return "square.stack.3d.up" }
        return file.isFolder ? "folder.fill" : file.isModel ? "cube" : "square.stack.3d.up.fill"
    }

    private var glyphTint: Color {
        guard let file else { return Palette.faint }
        return file.isFolder ? Palette.accent : file.isModel ? Palette.dust : tint
    }
}

/// Splits slicer-style file names into a readable title and settings tags.
/// PrusaSlicer's default is `{name}_{layer}mm_{material}_{printer}_{time}`, e.g.
/// `6-piece-hook-set_0.2mm_PETG_MK3S_2h16m.gcode` → "6-piece-hook-set" + [0.2mm, PETG, MK3S].
struct SlicedName {
    let title: String
    let tags: [String]

    init(_ filename: String) {
        // Drop the extension, and any repeat of it ("part.gcode.gcode" from an earlier download/re-upload).
        var base = filename
        while ["gcode", "gco", "g", "bgcode"].contains((base as NSString).pathExtension.lowercased()) {
            base = (base as NSString).deletingPathExtension
        }
        // A copy ("…_2h16m_copy", "…_2h16m_copy_2") keeps its slicer details; "copy" moves to the end of the title.
        var copy = ""
        if let match = base.firstMatch(of: /(?i)[_ ](copy(?:[_ ]\d+)?)$/) {
            copy = " " + match.1.replacingOccurrences(of: "_", with: " ")
            base.removeSubrange(match.range)
        }
        let parts = base.split(separator: "_").map(String.init)
        if parts.count >= 5,
           parts[parts.count - 4].range(of: #"^\d+(\.\d+)?mm$"#, options: .regularExpression) != nil,
           parts[parts.count - 1].range(of: #"^(\d+d)?(\d+h)?\d+m$"#, options: .regularExpression) != nil
        {
            title = parts.dropLast(4).joined(separator: "_").replacingOccurrences(of: "_", with: " ") + copy
            tags = Array(parts[(parts.count - 4)...(parts.count - 2)])
        } else {
            base += copy.replacingOccurrences(of: " ", with: "_")
            title = base.replacingOccurrences(of: "_", with: " ")
            tags = []
        }
    }
}

struct TagRow: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(Typeface.number(11))
                    .foregroundStyle(Palette.dust)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Palette.graphite))
            }
        }
    }
}

/// Everything about a file: a large thumbnail, the full name and location, size, upload details, the slicer's
/// analysis and the print history, with Open and Download.
struct FilePreview: View {
    let file: FileEntry
    let client: OctoPrintClient
    let filament: Color
    /// False hides the Open button (e.g. the file is already open, or the printer can't take it).
    let canOpen: Bool
    /// Shows a "Preview" button for G-code when set.
    var preview: (() -> Void)? = nil
    let open: () -> Void
    @State private var downloading = false
    @State private var downloadError: String?

    var body: some View {
        let name = SlicedName(file.displayName)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FileThumbnail(file: file, client: client, tint: filament, radius: 14)
                    .frame(height: file.thumbnail == nil ? 100 : 220)

                VStack(alignment: .leading, spacing: 6) {
                    Text(file.isFolder ? file.displayName : name.title)
                        .font(Typeface.title).foregroundStyle(Palette.paper).lineLimit(3)
                    if !name.tags.isEmpty { TagRow(tags: name.tags) }
                }

                section("File") {
                    row("Name", file.name, selectable: true)
                    row("Folder", folder)
                    row("Stored on", file.origin.isOnPrinter ? String(localized: "Printer's SD card") : String(localized: "OctoPrint (Raspberry Pi)"))
                    if let size = file.size {
                        row("Size", String(localized: "\(Fmt.bytes(size))  (\(size.formatted()) bytes)"))
                    }
                    if let date = file.date {
                        row("Added", "\(date.formatted(date: .long, time: .shortened))  (\(date.formatted(.relative(presentation: .named))))")
                    }
                    if let user = file.user { row("Added by", user) }
                    if let kind = file.typePath?.last { row("Type", kind.uppercased()) }
                }

                if let analysis = file.gcodeAnalysis {
                    section("Estimate") {
                        if let expected = file.expectedPrintTime {
                            row("Print time", Fmt.duration(expected.seconds) + " (\(Fmt.source(expected.source)))")
                        }
                        ForEach(analysis.filament.keys.sorted(), id: \.self) { tool in
                            let usage = analysis.filament[tool]
                            row(analysis.filament.count > 1 ? "Filament (\(HeaterKind(key: tool).displayName))" : "Filament" as LocalizedStringKey,
                                [usage?.length.map { Fmt.filament($0) }, usage?.volume.map { Fmt.decimal($0, 1) + " cm³" }]
                                    .compactMap { $0 }.joined(separator: ", "))
                        }
                        if let d = analysis.dimensions, let w = d.width, let dp = d.depth, let h = d.height {
                            row("Model size", "\(Fmt.number(w)) × \(Fmt.number(dp)) × \(Fmt.number(h)) mm")
                        }
                    }
                }

                if let prints = file.prints, (prints.success ?? 0) + (prints.failure ?? 0) > 0 {
                    section("Print history") {
                        row("Finished", "\(prints.success ?? 0)")
                        row("Failed or stopped", "\(prints.failure ?? 0)")
                        if let average = file.averagePrintTime?.values.first {
                            row("Average real time", Fmt.duration(average))
                        }
                        if let last = prints.last {
                            let when = last.date.map { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened) } ?? "–"
                            let result = last.success.map { $0 ? String(localized: "finished") : String(localized: "failed or stopped") }
                                ?? String(localized: "unknown result")
                            row("Last print", last.printTime.map { String(localized: "\(when), \(result), took \(Fmt.duration($0))") }
                                ?? String(localized: "\(when), \(result)"))
                        }
                    }
                }

                if let hash = file.hash {
                    row("SHA-1", hash, selectable: true, monospaced: true)
                }

                HStack(spacing: 10) {
                    if let downloadError {
                        Text(downloadError).font(Typeface.caption).foregroundStyle(Palette.hot).lineLimit(2)
                    }
                    Spacer()
                    if !file.isFolder && file.refs?.download != nil {
                        Button(action: download) {
                            if downloading { ProgressView().controlSize(.small) } else { Label("Download…", systemImage: "arrow.down.circle") }
                        }
                        .buttonStyle(.plateQuiet)
                        .disabled(downloading)
                    }
                    if file.isMachineCode, let preview {
                        Button(action: preview) { Label("Preview", systemImage: "square.stack.3d.up") }
                            .buttonStyle(.plateQuiet)
                    }
                    if file.isMachineCode && canOpen {
                        Button("Open", action: open).buttonStyle(.plate(filament))
                    }
                }
            }
            .padding(22)
        }
        .frame(width: 520)
        .frame(maxHeight: 980)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.extrusion)
    }

    private var folder: String {
        let parts = file.path.split(separator: "/").dropLast()
        return parts.isEmpty ? String(localized: "Top level") : parts.joined(separator: " / ")
    }

    @ViewBuilder
    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.dust)
            VStack(alignment: .leading, spacing: 7) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .machined(radius: 12, fill: Palette.graphite)
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String, selectable: Bool = false, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(Typeface.caption).foregroundStyle(Palette.faint).frame(width: 110, alignment: .leading)
            Group {
                if selectable { Text(value).textSelection(.enabled) } else { Text(value) }
            }
            .font(monospaced ? .system(size: 11, design: .monospaced) : Typeface.body)
            .foregroundStyle(Palette.paper)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func download() {
        downloading = true
        downloadError = nil
        Task {
            do {
                let data = try await client.download(file)
                let type = UTType(filenameExtension: (file.name as NSString).pathExtension) ?? .data
                SaveFile.present(data: data, name: file.name, type: type)
            } catch {
                downloadError = String(localized: "Couldn't download: \(error.localizedDescription)")
            }
            downloading = false
        }
    }
}
