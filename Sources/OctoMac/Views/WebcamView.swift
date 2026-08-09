import AppKit
import Observation
import SwiftUI

/// Displays a printer's camera. The stream itself lives on the `PrinterSession`, so it keeps running while
/// another printer is on screen and switching back is instant.
struct WebcamView: View {
    let streamer: MJPEGStreamer
    let transform: (flipH: Bool, flipV: Bool, rotate90: Bool)

    var body: some View {
        ZStack {
            Rectangle().fill(.black)
            if let frame = streamer.frame {
                // Soft fill behind the letterboxing so the camera feels full-bleed.
                Color.clear
                    .overlay {
                        Image(nsImage: frame)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 40)
                            .opacity(0.45)
                    }
                    .clipped()
                Image(nsImage: frame)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: transform.flipH ? -1 : 1, y: transform.flipV ? -1 : 1)
                    .rotationEffect(transform.rotate90 ? .degrees(-90) : .zero)
            } else if let failure = streamer.failure {
                VStack(spacing: 6) {
                    Image(systemName: "video.slash")
                    Text(failure).font(.caption).multilineTextAlignment(.center)
                    Text("Retrying automatically").font(.caption2)
                    Button("Retry now") { streamer.restart() }
                }
                .foregroundStyle(.secondary)
                .padding()
            } else {
                ProgressView()
            }
        }
        .onAppear { streamer.addViewer() }
        .onDisappear { streamer.removeViewer() }
    }
}

/// Long-lived MJPEG (multipart/x-mixed-replace) reader: scans the byte stream for JPEG SOI/EOI markers.
/// Also works for a single-JPEG snapshot URL. While nothing is showing it, frames are kept as raw data and
/// only decoded when it becomes visible, so background streams cost bandwidth but little CPU.
@MainActor
@Observable
final class MJPEGStreamer {
    private(set) var frame: NSImage?
    private(set) var failure: String?

    /// How many views are showing this stream (the main window and/or picture in picture). Frames are only decoded
    /// while at least one is.
    @ObservationIgnored private var viewers = 0
    var isVisible: Bool { viewers > 0 }

    func addViewer() {
        viewers += 1
        if viewers == 1, let latest { frame = NSImage(data: latest) }
    }

    func removeViewer() { viewers = max(0, viewers - 1) }

    @ObservationIgnored private var latest: Data?
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var apiKey: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var retry: Task<Void, Never>?

    /// The most recent frame exactly as the camera sent it (JPEG), for saving snapshots.
    var latestFrameData: Data? { latest }

    /// Starts streaming `url`, or does nothing if that stream is already running.
    func start(url: URL, apiKey: String?) {
        guard url != self.url || session == nil else { return }
        self.url = url
        self.apiKey = apiKey
        connect()
    }

    func restart() {
        guard url != nil else { return }
        connect()
    }

    func stop() {
        retry?.cancel()
        retry = nil
        generation += 1
        session?.invalidateAndCancel()
        session = nil
        url = nil
    }

    private func connect() {
        retry?.cancel()
        session?.invalidateAndCancel()
        generation += 1
        let current = generation
        failure = nil
        guard let url else { return }

        let delegate = StreamDelegate(
            onFrame: { [weak self] data in
                Task { @MainActor in self?.receive(data, generation: current) }
            },
            onEnd: { [weak self] message in
                Task { @MainActor in self?.ended(message, generation: current) }
            }
        )
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = .infinity
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        var request = URLRequest(url: url)
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key") }
        session.dataTask(with: request).resume()
        self.session = session
    }

    private func receive(_ data: Data, generation: Int) {
        guard generation == self.generation else { return }
        latest = data
        failure = nil
        if isVisible || frame == nil, let image = NSImage(data: data) { frame = image }
    }

    private func ended(_ message: String?, generation: Int) {
        // Ignore callbacks from a session we've already replaced.
        guard generation == self.generation else { return }
        failure = message ?? "The camera stream ended"
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.restart()
        }
    }
}

private final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    // Only touched from the session's serial delegate queue.
    private var buffer = Data()
    private let onFrame: @Sendable (Data) -> Void
    private let onEnd: @Sendable (String?) -> Void

    private static let soi = Data([0xFF, 0xD8])
    private static let eoi = Data([0xFF, 0xD9])

    init(onFrame: @escaping @Sendable (Data) -> Void, onEnd: @escaping @Sendable (String?) -> Void) {
        self.onFrame = onFrame
        self.onEnd = onEnd
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        var latest: Data?
        while let start = buffer.range(of: Self.soi),
              let end = buffer.range(of: Self.eoi, in: start.upperBound..<buffer.endIndex)
        {
            latest = buffer.subdata(in: start.lowerBound..<end.upperBound)
            buffer.removeSubrange(buffer.startIndex..<end.upperBound)
        }
        if let latest { onFrame(latest) }
        if buffer.count > 8_000_000 { buffer.removeAll(keepingCapacity: true) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as? URLError, error.code == .cancelled { return }
        if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            onEnd("Webcam returned HTTP \(http.statusCode)")
        } else if error == nil, task.response?.mimeType?.hasPrefix("image/") == true {
            // Single-image snapshot: nothing more to stream, keep the frame.
            return
        } else {
            onEnd(error?.localizedDescription)
        }
    }
}

/// Saving and copying the current camera frame, with OctoPrint's flip/rotate settings applied so the result
/// matches what's on screen.
enum Snapshot {
    typealias Transform = (flipH: Bool, flipV: Bool, rotate90: Bool)

    static func isIdentity(_ transform: Transform) -> Bool { !transform.flipH && !transform.flipV && !transform.rotate90 }

    /// The frame as a bitmap with the transform applied.
    static func bitmap(from jpeg: Data, transform: Transform) -> NSBitmapImageRep? {
        guard let source = NSBitmapImageRep(data: jpeg), let cgImage = source.cgImage else { return nil }
        if isIdentity(transform) { return source }
        let w = cgImage.width, h = cgImage.height
        let outW = transform.rotate90 ? h : w, outH = transform.rotate90 ? w : h
        guard let context = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: CGFloat(outW) / 2, y: CGFloat(outH) / 2)
        // OctoPrint's rotate90 is counter-clockwise.
        if transform.rotate90 { context.rotate(by: .pi / 2) }
        context.scaleBy(x: transform.flipH ? -1 : 1, y: transform.flipV ? -1 : 1)
        context.draw(cgImage, in: CGRect(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2, width: CGFloat(w), height: CGFloat(h)))
        return context.makeImage().map(NSBitmapImageRep.init(cgImage:))
    }

    static func jpeg(_ frame: Data, transform: Transform) -> Data? {
        // Untransformed frames are saved byte-for-byte, with no re-compression.
        if isIdentity(transform) { return frame }
        return bitmap(from: frame, transform: transform)?.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
    }

    static func png(_ frame: Data, transform: Transform) -> Data? {
        bitmap(from: frame, transform: transform)?.representation(using: .png, properties: [:])
    }

    static func fileName(printer: String, ext: String) -> String {
        let stamp = Date.now.formatted(.iso8601.year().month().day()) + " "
            + Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        return "\(printer) snapshot \(stamp).\(ext)".replacingOccurrences(of: ":", with: ".")
    }
}

/// Minimal dropdown on the camera for saving or copying the current frame.
struct SnapshotMenu: View {
    let session: PrinterSession
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            if copied {
                Text("Copied").font(Typeface.caption).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .transition(.opacity)
            }
            Menu {
                Button("Save snapshot (JPEG)…") { save(png: false) }
                Button("Save snapshot (PNG)…") { save(png: true) }
                Divider()
                Button("Copy snapshot") { copy() }
            } label: {
                QuietMenuLabel(symbol: "camera", onDark: true)
            }
            .quietMenu()
            .help("Save or copy the current camera frame")
        }
        .animation(.easeOut(duration: 0.2), value: copied)
    }

    private func save(png: Bool) {
        guard let frame = session.camera.latestFrameData else { return }
        let transform = session.webcamTransform
        guard let data = png ? Snapshot.png(frame, transform: transform) : Snapshot.jpeg(frame, transform: transform) else {
            session.error = ErrorBanner(message: "Couldn't read the current camera frame.")
            return
        }
        SaveFile.present(data: data, name: Snapshot.fileName(printer: session.instance.name, ext: png ? "png" : "jpg"),
                         type: png ? .png : .jpeg)
    }

    private func copy() {
        guard let frame = session.camera.latestFrameData,
              let bitmap = Snapshot.bitmap(from: frame, transform: session.webcamTransform) else { return }
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
