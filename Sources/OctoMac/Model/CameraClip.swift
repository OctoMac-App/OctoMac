import AVFoundation
import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// What to capture from a printer's camera, remembered between captures.
struct ClipSettings: Equatable {
    enum Mode: String, CaseIterable { case last, next, timelapse }
    enum Format: String, CaseIterable { case gif, mp4 }
    enum Size: Int, CaseIterable { case small = 480, medium = 720, full = 0 }

    var mode = Mode.next
    var format = Format.gif
    var size = Size.small
    /// Frames per second in the clip.
    var fps = 10
    /// Seconds to record for "Next".
    var seconds = 10
    /// Minutes a timelapse covers; it plays back in `timelapsePlayback` seconds.
    var timelapseMinutes = 5
    var loops = true

    static let timelapsePlayback = 6.0

    /// How long capturing takes, in seconds (none for "Last").
    var captureDuration: TimeInterval {
        switch mode {
        case .last: 0
        case .next: TimeInterval(seconds)
        case .timelapse: TimeInterval(timelapseMinutes * 60)
        }
    }

    /// Seconds between captured frames.
    var frameInterval: TimeInterval {
        mode == .timelapse ? captureDuration / (Self.timelapsePlayback * Double(fps)) : 1 / Double(fps)
    }
}

/// Records a GIF or MP4 from a printer's camera: the last few seconds, the next few, or a quick timelapse.
@MainActor
@Observable
final class ClipRecorder {
    enum Phase: Equatable {
        case idle
        case recording(progress: Double, secondsLeft: Int)
        case encoding
        case done(URL, bytes: Int)
        case failed(String)
    }

    private(set) var phase = Phase.idle
    @ObservationIgnored private var frames: [Data] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var started: TimeInterval = 0
    @ObservationIgnored private var settings = ClipSettings()
    @ObservationIgnored private var camera: MJPEGStreamer?
    @ObservationIgnored private var transform: Snapshot.Transform = (false, false, false)
    @ObservationIgnored private var name = "Camera"

    func start(_ settings: ClipSettings, camera: MJPEGStreamer, transform: Snapshot.Transform, name: String) {
        cancel()
        self.settings = settings
        self.camera = camera
        self.transform = transform
        self.name = name
        frames = []
        switch settings.mode {
        case .last:
            // Every so often from the last ten seconds, at the chosen smoothness.
            var next = 0.0
            for frame in camera.recentFrames.suffix(while: { camera.recentFrames.last!.time - $0.time <= 10 }) where frame.time >= next {
                frames.append(frame.jpeg)
                next = frame.time + settings.frameInterval * 0.9
            }
            // A still camera (or demo mode) still makes a short clip.
            if frames.count < 2, let still = camera.latestFrameData { frames = Array(repeating: still, count: settings.fps * 3) }
            finish()
        case .next, .timelapse:
            started = ProcessInfo.processInfo.systemUptime
            capture()
            timer = Timer.scheduledTimer(withTimeInterval: settings.frameInterval, repeats: true) { _ in
                MainActor.assumeIsolated { self.capture() }
            }
            phase = .recording(progress: 0, secondsLeft: Int(settings.captureDuration))
        }
    }

    /// Ends the recording early and makes the clip from what's been captured.
    func stop() {
        guard case .recording = phase else { return }
        finish()
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        frames = []
        if case .done(let url, _) = phase { try? FileManager.default.removeItem(at: url) }
        phase = .idle
    }

    private func capture() {
        if let frame = camera?.latestFrameData { frames.append(frame) }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let total = settings.captureDuration
        if elapsed >= total {
            finish()
        } else {
            phase = .recording(progress: elapsed / total, secondsLeft: Int((total - elapsed).rounded(.up)))
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        guard frames.count >= 2 else {
            phase = .failed(String(localized: "The camera didn't send any pictures. Check it's working, then try again."))
            return
        }
        phase = .encoding
        let frames = self.frames, settings = self.settings, transform = self.transform
        let stamp = Date.now.formatted(.iso8601.year().month().day()) + " "
            + Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        let file = (settings.mode == .timelapse ? String(localized: "\(name) timelapse \(stamp)") : String(localized: "\(name) clip \(stamp)"))
            .replacingOccurrences(of: ":", with: ".")
        let url = FileManager.default.temporaryDirectory.appending(path: "OctoMac clips", directoryHint: .isDirectory)
            .appending(path: "\(file).\(settings.format == .gif ? "gif" : "mp4")")
        self.frames = []
        Task.detached(priority: .userInitiated) {
            let result = ClipEncoder.encode(frames, to: url, settings: settings, transform: transform)
            await MainActor.run {
                switch result {
                case .success(let bytes): self.phase = .done(url, bytes: bytes)
                case .failure(let error): self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }
}

private extension Array {
    /// The longest run at the end of the array whose elements all pass `test`.
    func suffix(while test: (Element) -> Bool) -> ArraySlice<Element> {
        var start = endIndex
        while start > startIndex, test(self[start - 1]) { start -= 1 }
        return self[start...]
    }
}

/// Turns camera JPEGs into an animated GIF or an H.264 MP4.
enum ClipEncoder {
    struct Failure: LocalizedError {
        var errorDescription: String?
    }

    static func encode(_ frames: [Data], to url: URL, settings: ClipSettings, transform: Snapshot.Transform) -> Result<Int, Error> {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        let images = frames.compactMap { image(from: $0, transform: transform, width: settings.size.rawValue) }
        guard images.count >= 2 else { return .failure(Failure(errorDescription: String(localized: "Couldn't read the camera's pictures."))) }
        do {
            switch settings.format {
            case .gif: try gif(images, to: url, fps: settings.fps, loops: settings.loops)
            case .mp4: try mp4(images, to: url, fps: settings.fps)
            }
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return .success(bytes)
        } catch {
            return .failure(error)
        }
    }

    /// A frame turned the way it shows on screen and scaled to `width` (0 keeps the camera's size, up to 1920).
    /// Width and height are kept even, as H.264 needs.
    private static func image(from jpeg: Data, transform: Snapshot.Transform, width: Int) -> CGImage? {
        guard let source = Snapshot.bitmap(from: jpeg, transform: transform)?.cgImage else { return nil }
        let targetWidth = min(width == 0 ? source.width : width, source.width, 1920)
        let w = targetWidth / 2 * 2
        let h = Int((Double(source.height) * Double(w) / Double(source.width)).rounded()) / 2 * 2
        guard w > 0, h > 0, let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }

    private static func gif(_ images: [CGImage], to url: URL, fps: Int, loops: Bool) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, images.count, nil) else {
            throw Failure(errorDescription: String(localized: "Couldn't create the GIF."))
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loops ? 0 : 1],
        ] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(fps)]] as CFDictionary
        for image in images { CGImageDestinationAddImage(destination, image, frame) }
        guard CGImageDestinationFinalize(destination) else { throw Failure(errorDescription: String(localized: "Couldn't finish the GIF.")) }
    }

    private static func mp4(_ images: [CGImage], to url: URL, fps: Int) throws {
        let w = images[0].width, h = images[0].height
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(600_000, w * h * 3)],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure(errorDescription: String(localized: "Couldn't start the video.")) }
        writer.startSession(atSourceTime: .zero)
        for (index, image) in images.enumerated() {
            while !input.isReadyForMoreMediaData { usleep(2_000) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: w, height: h, bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed { throw writer.error ?? Failure(errorDescription: String(localized: "Couldn't finish the video.")) }
    }
}
