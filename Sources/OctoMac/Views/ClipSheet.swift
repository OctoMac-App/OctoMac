import AVKit
import SwiftUI
import UniformTypeIdentifiers

/// Record a GIF or MP4 from the camera: the last ten seconds, the next few, or a quick timelapse.
struct ClipSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    @State private var recorder = ClipRecorder()
    @State private var showsMore = false

    // Remembered, so the next clip is one click.
    @AppStorage("clip.mode") private var mode = ClipSettings.Mode.next.rawValue
    @AppStorage("clip.format") private var format = ClipSettings.Format.gif.rawValue
    @AppStorage("clip.size") private var size = ClipSettings.Size.small.rawValue
    @AppStorage("clip.fps") private var fps = 10
    @AppStorage("clip.seconds") private var seconds = 10
    @AppStorage("clip.timelapseMinutes") private var timelapseMinutes = 5
    @AppStorage("clip.loops") private var loops = true

    private var settings: ClipSettings {
        ClipSettings(mode: ClipSettings.Mode(rawValue: mode) ?? .next, format: ClipSettings.Format(rawValue: format) ?? .gif,
                     size: ClipSettings.Size(rawValue: size) ?? .small, fps: fps, seconds: seconds,
                     timelapseMinutes: timelapseMinutes, loops: loops)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Record a clip").font(Typeface.title).foregroundStyle(Palette.paper)
                Spacer()
                Text(session.instance.name).font(Typeface.caption).foregroundStyle(Palette.faint)
            }
            switch recorder.phase {
            case .idle: choose
            case .recording(let progress, let secondsLeft): recording(progress: progress, secondsLeft: secondsLeft)
            case .encoding: working("Making the \(settings.format == .gif ? "GIF" : "video")…")
            case .done(let url, let bytes): result(url: url, bytes: bytes)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").font(Typeface.body).foregroundStyle(Palette.hot)
                HStack { Spacer(); Button("Try again") { recorder.cancel() }.buttonStyle(.plate) }
            }
        }
        .padding(26)
        .frame(width: 560)
        .background(Palette.extrusion)
        .onDisappear { recorder.cancel() }
    }

    // MARK: Choosing

    private var choose: some View {
        VStack(alignment: .leading, spacing: 16) {
            row("Capture") {
                CapsulePicker(selection: $mode, options: [(ClipSettings.Mode.last.rawValue, "Last 10 seconds"),
                                                          (ClipSettings.Mode.next.rawValue, "Next few seconds"),
                                                          (ClipSettings.Mode.timelapse.rawValue, "Timelapse")])
            }
            if mode == ClipSettings.Mode.next.rawValue {
                row("Length") { CapsulePicker(selection: $seconds, options: [(5, "5 seconds"), (10, "10 seconds"), (30, "30 seconds")], compact: true) }
            } else if mode == ClipSettings.Mode.timelapse.rawValue {
                row("Over") { CapsulePicker(selection: $timelapseMinutes, options: [(1, "1 minute"), (5, "5 minutes"), (15, "15 minutes"), (60, "1 hour")], compact: true) }
            }
            row("Format") {
                CapsulePicker(selection: $format, options: [(ClipSettings.Format.gif.rawValue, "GIF"), (ClipSettings.Format.mp4.rawValue, "MP4")], compact: true)
            }
            Text(summary).font(Typeface.caption).foregroundStyle(Palette.faint).fixedSize(horizontal: false, vertical: true)

            Button {
                withAnimation(.snappy(duration: 0.2)) { showsMore.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(showsMore ? 90 : 0))
                    Text("More options").font(Typeface.bodyStrong)
                }
                .foregroundStyle(Palette.dust)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsMore {
                VStack(alignment: .leading, spacing: 12) {
                    row("Size") {
                        CapsulePicker(selection: $size, options: [(ClipSettings.Size.small.rawValue, "Small"), (ClipSettings.Size.medium.rawValue, "Medium"),
                                                                  (ClipSettings.Size.full.rawValue, "Camera size")], compact: true)
                    }
                    row("Smoothness") { CapsulePicker(selection: $fps, options: [(5, "5 fps"), (10, "10 fps"), (15, "15 fps")], compact: true) }
                    if format == ClipSettings.Format.gif.rawValue {
                        row("Play") { CapsulePicker(selection: $loops, options: [(true, "On a loop"), (false, "Once")], compact: true) }
                    }
                }
                .transition(.opacity)
            }

            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.plateQuiet).keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    recorder.start(settings, camera: session.camera, transform: session.webcamTransform, name: session.instance.name)
                } label: {
                    Label(mode == ClipSettings.Mode.last.rawValue ? "Make clip" : "Start recording", systemImage: "record.circle")
                }
                .buttonStyle(.plate)
                .keyboardShortcut(.defaultAction)
                .disabled(session.camera.latestFrameData == nil)
            }
        }
    }

    private var summary: String {
        let s = settings
        let size = s.size == .full ? "at the camera's size" : "\(s.size.rawValue) pixels wide"
        switch s.mode {
        case .last: return "The last 10 seconds of the camera, \(size). Good for catching something that just happened."
        case .next: return "Records the next \(s.seconds) seconds, \(size)."
        case .timelapse:
            let span = s.timelapseMinutes == 60 ? "an hour" : s.timelapseMinutes == 1 ? "a minute" : "\(s.timelapseMinutes) minutes"
            return "A picture every \(Fmt.duration(s.frameInterval)) over \(span), played back in \(Int(ClipSettings.timelapsePlayback)) seconds, \(size). Keep this window open while it records."
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.dust).frame(width: 90, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    // MARK: Recording

    private func recording(progress: Double, secondsLeft: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(Palette.hot).frame(width: 10, height: 10).shadow(color: Palette.hot, radius: 4)
                Text("Recording").font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                Spacer()
                Text(Fmt.duration(Double(secondsLeft)) + " left").font(Typeface.number(15)).foregroundStyle(Palette.dust)
            }
            ProgressView(value: progress).tint(Palette.hot)
            HStack {
                Button("Cancel") { recorder.cancel() }.buttonStyle(.plateQuiet)
                Spacer()
                Button { recorder.stop() } label: { Label("Stop and keep", systemImage: "stop.fill") }
                    .buttonStyle(.plate)
                    .help("Make the clip from what's been recorded so far")
            }
        }
    }

    private func working(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(Palette.accent)
            Text(text).font(Typeface.body).foregroundStyle(Palette.dust)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }

    // MARK: Result

    private func result(url: URL, bytes: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ClipPreview(url: url)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 10) {
                Text(url.lastPathComponent).font(Typeface.caption).foregroundStyle(Palette.faint).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(Fmt.bytes(bytes)).font(Typeface.number(13)).foregroundStyle(Palette.dust)
            }
            HStack(spacing: 10) {
                Button("Record another") { recorder.cancel() }.buttonStyle(.plateQuiet)
                Spacer()
                ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(.plateQuiet)
                Button { copy(url) } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(.plateQuiet)
                Button { save(url) } label: { Label("Save…", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.plate)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// Copies the file, so it pastes into Messages, Discord, Slack or Finder as an attachment.
    private func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    private func save(_ url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.allowedContentTypes = [url.pathExtension == "gif" ? .gif : .mpeg4Movie]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: url, to: destination)
        }
    }
}

/// Plays the finished clip on a loop: an animated image for a GIF, a muted looping video for an MP4.
private struct ClipPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        if url.pathExtension == "gif" {
            let view = NSImageView()
            view.image = NSImage(contentsOf: url)
            view.animates = true
            view.imageScaling = .scaleProportionallyUpOrDown
            return view
        }
        let view = AVPlayerView()
        view.controlsStyle = .none
        let player = AVQueuePlayer()
        player.isMuted = true
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.player = player
        player.play()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }
}
