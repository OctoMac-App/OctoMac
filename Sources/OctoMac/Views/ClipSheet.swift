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
            case .encoding: working(settings.format == .gif ? "Making the GIF…" : "Making the video…")
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
                row("Duration") { CapsulePicker(selection: $timelapseMinutes, options: [(1, "1 minute"), (5, "5 minutes"), (15, "15 minutes"), (60, "1 hour")], compact: true) }
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
        let size = s.size == .full ? String(localized: "at the camera's size") : String(localized: "\(s.size.rawValue) pixels wide")
        switch s.mode {
        case .last: return String(localized: "The last 10 seconds of the camera, \(size). Good for catching something that just happened.")
        case .next: return String(localized: "Records the next \(s.seconds) seconds, \(size).")
        case .timelapse:
            let span = Duration.seconds(Double(s.timelapseMinutes * 60)).formatted(.units(allowed: [.hours, .minutes], width: .wide))
            return String(localized: "A picture every \(Fmt.duration(s.frameInterval)) over \(span), played back in \(Int(ClipSettings.timelapsePlayback)) seconds, \(size). Keep this window open while it records.")
        }
    }

    private func row<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
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

    private func working(_ text: LocalizedStringKey) -> some View {
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

/// Plays the finished clip on a loop, with app-style controls: play and pause, and for videos a scrubber and the time.
private struct ClipPreview: View {
    let url: URL
    @State private var video: LoopingVideo?
    @State private var gifPlaying = true

    private var isGIF: Bool { url.pathExtension == "gif" }

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if isGIF {
                    AnimatedImage(url: url, playing: gifPlaying)
                } else if let video {
                    VideoSurface(player: video.player)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { togglePlaying() }

            HStack(spacing: 12) {
                Button(action: togglePlaying) {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                }
                .buttonStyle(KeyButtonStyle(size: CGSize(width: 36, height: 32)))
                .keyboardShortcut(.space, modifiers: [])
                .help(playing ? "Pause (Space)" : "Play (Space)")

                if let video {
                    Scrubber(video: video)
                    Text("\(Self.time(video.time)) / \(Self.time(video.duration))")
                        .font(Typeface.number(13))
                        .foregroundStyle(Palette.dust)
                        .monospacedDigit()
                        .fixedSize()
                } else {
                    Text(gifPlaying ? "Playing on a loop" : "Paused")
                        .font(Typeface.caption)
                        .foregroundStyle(Palette.faint)
                    Spacer()
                }
            }
        }
        .onAppear { if !isGIF { video = LoopingVideo(url: url) } }
        .onDisappear { video?.player.pause() }
    }

    private var playing: Bool { video?.isPlaying ?? gifPlaying }

    private func togglePlaying() {
        if let video { video.toggle() } else { gifPlaying.toggle() }
    }

    static func time(_ seconds: Double) -> String {
        let whole = Int(seconds.isFinite ? seconds : 0)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// A muted video that loops, and reports where it's up to for the controls.
@MainActor
@Observable
private final class LoopingVideo {
    let player = AVQueuePlayer()
    private(set) var time: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying = true
    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private var observer: Any?
    /// While dragging the scrubber, it shows where you're dragging rather than where the video is.
    @ObservationIgnored var scrubbing = false

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: item)
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] now in
            MainActor.assumeIsolated {
                guard let self, !self.scrubbing else { return }
                self.time = now.seconds
                if let length = self.player.currentItem?.duration.seconds, length.isFinite { self.duration = length }
            }
        }
        player.play()
    }

    func toggle() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func seek(to fraction: Double) {
        guard duration > 0 else { return }
        time = duration * min(max(fraction, 0), 1)
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

/// The app's progress bar, which you can click or drag to move through the video.
private struct Scrubber: View {
    let video: LoopingVideo
    @State private var hovering = false
    @State private var wasPlaying = false

    var body: some View {
        GeometryReader { geo in
            let fraction = video.duration > 0 ? video.time / video.duration : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.graphite)
                    .overlay(Capsule().strokeBorder(Palette.edge, lineWidth: 1))
                Capsule().fill(Palette.accent)
                    .frame(width: max(8, geo.size.width * fraction))
                Circle()
                    .fill(Palette.paper)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: min(max(0, geo.size.width * fraction - 7), geo.size.width - 14))
                    .opacity(hovering || video.scrubbing ? 1 : 0)
            }
            .frame(height: 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !video.scrubbing {
                            video.scrubbing = true
                            wasPlaying = video.isPlaying
                            if wasPlaying { video.toggle() }
                        }
                        video.seek(to: value.location.x / max(1, geo.size.width))
                    }
                    .onEnded { _ in
                        video.scrubbing = false
                        if wasPlaying { video.toggle() }
                    }
            )
        }
        .frame(height: 32)
        .help("Drag to move through the clip")
    }
}

private struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}
}

/// An animated GIF that can be paused.
private struct AnimatedImage: NSViewRepresentable {
    let url: URL
    let playing: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(contentsOf: url)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = playing
        // Fit the space it's given; left to itself, the view asks for the GIF's full size and widens the sheet.
        for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            view.setContentCompressionResistancePriority(.defaultLow, for: orientation)
            view.setContentHuggingPriority(.defaultLow, for: orientation)
        }
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        view.animates = playing
    }
}
