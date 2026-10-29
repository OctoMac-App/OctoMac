import AVFoundation
import AppKit
import ImageIO
import Testing
@testable import OctoMac

struct ClipEncoderTests {
    /// Small JPEG frames that change colour, like a camera would send.
    private func frames(_ count: Int) -> [Data] {
        (0..<count).compactMap { index in
            let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(red: Double(index) / Double(count), green: 0.5, blue: 0.3, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .jpeg, properties: [:])
        }
    }

    private func output(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "octomac-test-\(UUID().uuidString).\(ext)")
    }

    @Test func makesAnAnimatedGIFAtTheChosenSize() throws {
        let url = output("gif")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = ClipSettings()
        settings.format = .gif
        settings.size = .small
        let bytes = try ClipEncoder.encode(frames(12), to: url, settings: settings, transform: (false, false, false)).get()
        #expect(bytes > 0)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 12)
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(first.width == 480)
        #expect(first.height == 360)
    }

    @Test func makesAnMP4OfTheRightLength() async throws {
        let url = output("mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = ClipSettings()
        settings.format = .mp4
        settings.fps = 10
        settings.size = .medium
        let bytes = try ClipEncoder.encode(frames(20), to: url, settings: settings, transform: (false, true, false)).get()
        #expect(bytes > 0)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 2) < 0.2)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size.width == 640)
        #expect(size.height == 480)
    }

    @Test func timelapseSpreadsFramesOverTheWholeTime() {
        var settings = ClipSettings()
        settings.mode = .timelapse
        settings.timelapseMinutes = 5
        settings.fps = 10
        // 300 seconds played back in 6 at 10 fps: 60 frames, one every 5 seconds.
        #expect(abs(settings.frameInterval - 5) < 0.001)
    }
}
