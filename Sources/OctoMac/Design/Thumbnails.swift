import AppKit
import OctoPrintKit
import SwiftUI

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
            if let apiKey = client.apiKey { request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key") }
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
        let base = (filename as NSString).deletingPathExtension
        let parts = base.split(separator: "_").map(String.init)
        if parts.count >= 5,
           parts[parts.count - 4].range(of: #"^\d+(\.\d+)?mm$"#, options: .regularExpression) != nil,
           parts[parts.count - 1].range(of: #"^(\d+d)?(\d+h)?\d+m$"#, options: .regularExpression) != nil
        {
            title = parts.dropLast(4).joined(separator: "_").replacingOccurrences(of: "_", with: " ")
            tags = Array(parts[(parts.count - 4)...(parts.count - 2)])
        } else {
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

/// Larger look at a file: its thumbnail at full size with the details you'd check before printing.
struct FilePreview: View {
    let file: FileEntry
    let client: OctoPrintClient
    let filament: Color
    /// False hides the Open button (e.g. the file is already open).
    let canOpen: Bool
    let open: () -> Void

    var body: some View {
        let name = SlicedName(file.displayName)
        VStack(alignment: .leading, spacing: 16) {
            FileThumbnail(file: file, client: client, tint: filament, radius: 14)
                .frame(width: 440, height: 330)

            VStack(alignment: .leading, spacing: 6) {
                Text(name.title).font(Typeface.title).foregroundStyle(Palette.paper).lineLimit(2)
                if !name.tags.isEmpty { TagRow(tags: name.tags) }
                Text(file.name).font(Typeface.caption).foregroundStyle(Palette.faint).textSelection(.enabled)
            }

            HStack(alignment: .top, spacing: 26) {
                fact("Print time", Fmt.duration(file.gcodeAnalysis?.estimatedPrintTime))
                fact("Filament", Fmt.filament(file.gcodeAnalysis?.totalFilamentLength))
                if let dimensions = file.gcodeAnalysis?.dimensions, let width = dimensions.width, let depth = dimensions.depth, let height = dimensions.height {
                    fact("Size", "\(Fmt.number(width)) × \(Fmt.number(depth)) × \(Fmt.number(height)) mm")
                }
            }
            HStack(alignment: .top, spacing: 26) {
                fact("Added", file.date?.formatted(date: .abbreviated, time: .shortened) ?? "–")
                if let prints = file.prints {
                    fact("Printed", "\(prints.success ?? 0) ok, \(prints.failure ?? 0) failed")
                }
            }

            if file.isMachineCode && canOpen {
                HStack {
                    Spacer()
                    Button("Open", action: open).buttonStyle(.plate(filament))
                }
            }
        }
        .padding(22)
        .frame(width: 484)
        .background(Palette.extrusion)
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Typeface.caption).foregroundStyle(Palette.faint)
            Text(value).font(Typeface.number(16)).foregroundStyle(Palette.paper)
        }
    }
}
