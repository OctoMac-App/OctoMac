// Renders the OctoMac logo lockup (octopus mark + wordmark) to PNG, for the README and anywhere else outside the app.
// Usage: swift scripts/make-logo.swift Support/OctoMark.png docs/logo-dark.png dark
//        swift scripts/make-logo.swift Support/OctoMark.png docs/logo-light.png light
// The in-app version is `BrandLockup` in Sources/OctoMac/Design/Brand.swift; keep the two in step.

import AppKit

let args = CommandLine.arguments
let mark = NSImage(contentsOfFile: args[1])!
let output = URL(fileURLWithPath: args[2])
let onDark = args.count < 4 || args[3] != "light"

let scale: CGFloat = 2
let markSize: CGFloat = 160, fontSize: CGFloat = 96, gap: CGFloat = 36, padding: CGFloat = 24
let font = NSFont(name: "AvenirNext-Bold", size: fontSize) ?? .boldSystemFont(ofSize: fontSize)
let green = NSColor(srgbRed: 0x5C / 255, green: 0xCB / 255, blue: 0x66 / 255, alpha: 1)
let second = onDark ? NSColor(srgbRed: 0xEC / 255, green: 0xE6 / 255, blue: 0xD8 / 255, alpha: 1)
                    : NSColor(srgbRed: 0x1C / 255, green: 0x20 / 255, blue: 0x26 / 255, alpha: 1)
let first = onDark ? green : NSColor(srgbRed: 0x23 / 255, green: 0x8A / 255, blue: 0x3B / 255, alpha: 1)

let word = NSMutableAttributedString()
word.append(NSAttributedString(string: "Octo", attributes: [.font: font, .foregroundColor: first, .kern: -fontSize * 0.02]))
word.append(NSAttributedString(string: "Mac", attributes: [.font: font, .foregroundColor: second, .kern: -fontSize * 0.02]))
let wordSize = word.size()

let width = padding * 2 + markSize + gap + wordSize.width
let height = padding * 2 + markSize
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
mark.draw(in: NSRect(x: padding, y: padding, width: markSize, height: markSize))
// Vertically centre the wordmark's cap height on the mark.
let baselineY = padding + markSize / 2 - (font.capHeight / 2)
word.draw(at: NSPoint(x: padding + markSize + gap, y: baselineY + font.descender))
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: output)
print("Wrote \(output.path)")
