import AppKit
import SwiftUI

/// The OctoMac logo: the winking octopus mark beside the wordmark.
/// The mark is `Support/OctoMark.png` (drawn by `scripts/make-icon.swift`), bundled into the app's Resources.
struct BrandLockup: View {
    /// Height of the octopus mark; the wordmark scales with it.
    var markSize: CGFloat = 30

    var body: some View {
        HStack(spacing: markSize * 0.28) {
            BrandMark().frame(width: markSize, height: markSize)
            Wordmark(size: markSize * 0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("OctoMac")
    }
}

/// "OctoMac" set in Avenir Next: "Octo" in the octopus's green, "Mac" in the interface's paper colour.
struct Wordmark: View {
    var size: CGFloat = 18

    static let green = Color(hex: 0x5CCB66)

    var body: some View {
        (Text("Octo").foregroundStyle(Self.green) + Text("Mac").foregroundStyle(Palette.paper))
            .font(Typeface.text(size, .bold))
            .tracking(-size * 0.02)
            .fixedSize()
    }
}

struct BrandMark: View {
    var body: some View {
        if let image = Self.image {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(systemName: "circle.fill").resizable().scaledToFit().foregroundStyle(Wordmark.green)
        }
    }

    /// The bundled mark, falling back to the app icon when running outside the .app (e.g. `swift run`).
    static let image: NSImage? = {
        if let url = Bundle.main.url(forResource: "OctoMark", withExtension: "png"), let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp?.applicationIconImage
    }()
}
