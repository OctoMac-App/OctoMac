// Draws the OctoMac app icon (a winking green octopus) and writes an .iconset.
// Usage: swift scripts/make-icon.swift <output.iconset>   then: iconutil -c icns <output.iconset>
//        swift scripts/make-icon.swift Support/OctoMark.png   (the octopus alone, for the in-app logo)
// Everything is drawn as vector paths on a 1024-point canvas, so each size renders crisply.

import AppKit
import CoreGraphics

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

// MARK: Octopus

let greenLight: UInt32 = 0x6BD66F, green: UInt32 = 0x34B24A, greenDark: UInt32 = 0x1E7E39, sucker: UInt32 = 0xD4F5C6

struct Arm {
    let p0, p1, p2, p3: CGPoint
    let baseWidth: CGFloat
    let tipWidth: CGFloat

    func point(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }

    func normal(_ t: CGFloat) -> CGPoint {
        let a = point(max(0, t - 0.001)), b = point(min(1, t + 0.001))
        let dx = b.x - a.x, dy = b.y - a.y, length = max(0.0001, sqrt(dx * dx + dy * dy))
        return CGPoint(x: -dy / length, y: dx / length)
    }

    func width(_ t: CGFloat) -> CGFloat { baseWidth + (tipWidth - baseWidth) * pow(t, 0.9) }

    func outline(scale: CGFloat = 1, shift: CGFloat = 0, end: CGFloat = 1) -> CGPath {
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...90 {
            let t = CGFloat(i) / 90 * end
            let p = point(t), n = normal(t), w = width(t)
            let c = CGPoint(x: p.x + n.x * w * shift, y: p.y + n.y * w * shift)
            left.append(CGPoint(x: c.x + n.x * w * scale / 2, y: c.y + n.y * w * scale / 2))
            right.append(CGPoint(x: c.x - n.x * w * scale / 2, y: c.y - n.y * w * scale / 2))
        }
        let path = CGMutablePath()
        path.addLines(between: left + right.reversed())
        path.closeSubpath()
        let tip = point(end), r = width(end) * scale / 2
        path.addEllipse(in: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2))
        return path
    }
}

func drawArm(_ ctx: CGContext, _ arm: Arm) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 14, color: color(0x000000, 0.28))
    ctx.addPath(arm.outline())
    ctx.setFillColor(color(greenDark))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(arm.outline(scale: 0.62, shift: 0.14, end: 0.98))
    ctx.setFillColor(color(green))
    ctx.fillPath()
    ctx.addPath(arm.outline(scale: 0.22, shift: 0.26, end: 0.9))
    ctx.setFillColor(color(greenLight, 0.75))
    ctx.fillPath()
    // A few suckers along the underside
    var t: CGFloat = 0.42
    while t < 0.9 {
        let p = arm.point(t), n = arm.normal(t), w = arm.width(t)
        let c = CGPoint(x: p.x - n.x * w * 0.3, y: p.y - n.y * w * 0.3)
        let r = max(3, w * 0.15)
        ctx.setFillColor(color(sucker, 0.9))
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        t += 0.14
    }
}

func drawHead(_ ctx: CGContext, center: CGPoint) {
    let head = CGRect(x: center.x - 190, y: center.y - 172, width: 380, height: 336)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x000000, 0.25))
    ctx.setFillColor(color(green))
    ctx.fillEllipse(in: head)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: head)
    ctx.clip()
    ctx.drawLinearGradient(gradient([color(greenLight), color(green), color(greenDark)]),
                           start: CGPoint(x: head.minX + 40, y: head.minY), end: CGPoint(x: head.maxX - 40, y: head.maxY), options: [])
    // Soft highlight on the dome
    ctx.drawRadialGradient(gradient([color(0xFFFFFF, 0.35), color(0xFFFFFF, 0)]),
                           startCenter: CGPoint(x: head.minX + 125, y: head.minY + 90), startRadius: 0,
                           endCenter: CGPoint(x: head.minX + 125, y: head.minY + 90), endRadius: 120, options: [])
    ctx.restoreGState()

    // The wink is the app's face; OCTO_ICON_FACE=smile or =flushed renders the alternatives.
    switch ProcessInfo.processInfo.environment["OCTO_ICON_FACE"] ?? "wink" {
    case "flushed":
        drawFlushedFace(ctx, center: center)
        return
    case "smile":
        break
    default:
        drawWinkFace(ctx, center: center)
        return
    }

    // Eyes: simple, slightly oval, looking up-right
    for dx in [CGFloat(-74), 74] {
        let eye = CGRect(x: center.x + dx - 42, y: center.y - 30, width: 84, height: 94)
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillEllipse(in: eye)
        ctx.setFillColor(color(0x14261A))
        ctx.fillEllipse(in: CGRect(x: eye.midX - 17, y: eye.midY - 26, width: 40, height: 45))
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillEllipse(in: CGRect(x: eye.midX - 6, y: eye.midY - 19, width: 13, height: 13))
    }
    // A small, gentle smile
    ctx.setStrokeColor(color(greenDark))
    ctx.setLineWidth(9)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: center.x, y: center.y + 72), radius: 30, startAngle: .pi * 0.2, endAngle: .pi * 0.8, clockwise: false)
    ctx.strokePath()
}

/// Alternative face (`OCTO_ICON_FACE=flushed`): huge wide-open eyes with small pupils, rosy cheeks, a small flat mouth.
func drawFlushedFace(_ ctx: CGContext, center: CGPoint) {
    let ink = color(0x14261A)
    // Rosy cheeks first, so the eyes sit over their edges
    for dx in [CGFloat(-104), 104] {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 10, color: color(0xFF6F8C, 0.5))
        ctx.setFillColor(color(0xFF8CA6, 0.92))
        ctx.fillEllipse(in: CGRect(x: center.x + dx - 34, y: center.y + 66, width: 68, height: 32))
        ctx.restoreGState()
    }
    // Big round eyes with small, centred pupils
    for dx in [CGFloat(-72), 72] {
        let eye = CGRect(x: center.x + dx - 56, y: center.y - 52, width: 112, height: 116)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 6, color: color(0x000000, 0.18))
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillEllipse(in: eye)
        ctx.restoreGState()
        ctx.setFillColor(ink)
        ctx.fillEllipse(in: CGRect(x: eye.midX - 15, y: eye.midY - 15, width: 30, height: 32))
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillEllipse(in: CGRect(x: eye.midX - 6, y: eye.midY - 10, width: 9, height: 9))
    }
    // Small, flat mouth
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(9)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: center.x - 20, y: center.y + 104))
    ctx.addLine(to: CGPoint(x: center.x + 20, y: center.y + 104))
    ctx.strokePath()
}

/// The app's face: one eye winking, one wide open, grinning with the tongue out.
func drawWinkFace(_ ctx: CGContext, center: CGPoint) {
    let ink = color(0x14261A)
    // Winking eye: a bold upward arch
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(13)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: center.x - 74, y: center.y + 28), radius: 32, startAngle: .pi * 1.12, endAngle: .pi * 1.88, clockwise: false)
    ctx.strokePath()

    // Open eye, a touch bigger, looking slightly up
    let eye = CGRect(x: center.x + 74 - 46, y: center.y - 42, width: 92, height: 102)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: eye)
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(x: eye.midX - 19, y: eye.midY - 28, width: 42, height: 48))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: eye.midX - 7, y: eye.midY - 21, width: 14, height: 14))

    // Grinning mouth
    let mouthCenter = CGPoint(x: center.x + 4, y: center.y + 78)
    let mouth = CGMutablePath()
    mouth.move(to: CGPoint(x: mouthCenter.x - 58, y: mouthCenter.y - 8))
    mouth.addQuadCurve(to: CGPoint(x: mouthCenter.x + 58, y: mouthCenter.y - 8), control: CGPoint(x: mouthCenter.x, y: mouthCenter.y + 2))
    mouth.addQuadCurve(to: CGPoint(x: mouthCenter.x - 58, y: mouthCenter.y - 8), control: CGPoint(x: mouthCenter.x, y: mouthCenter.y + 70))
    mouth.closeSubpath()
    ctx.addPath(mouth)
    ctx.setFillColor(color(0x123019))
    ctx.fillPath()

    // Tongue, hanging out over the lower lip to one side. Its back end is hidden inside the mouth.
    let leftCorner = CGPoint(x: mouthCenter.x - 58, y: mouthCenter.y - 8)
    let rightCorner = CGPoint(x: mouthCenter.x + 58, y: mouthCenter.y - 8)
    let lowerLipControl = CGPoint(x: mouthCenter.x, y: mouthCenter.y + 70)
    // Only the part of the tongue below a line just inside the lower lip shows, so it rests on the lip and the dark
    // mouth stays visible above it.
    let tongueClip = CGMutablePath()
    tongueClip.move(to: CGPoint(x: leftCorner.x, y: leftCorner.y + 10))
    tongueClip.addQuadCurve(to: CGPoint(x: rightCorner.x, y: rightCorner.y + 10),
                            control: CGPoint(x: lowerLipControl.x, y: lowerLipControl.y - 30))
    tongueClip.addLine(to: CGPoint(x: rightCorner.x + 60, y: mouthCenter.y + 300))
    tongueClip.addLine(to: CGPoint(x: leftCorner.x - 60, y: mouthCenter.y + 300))
    tongueClip.closeSubpath()

    ctx.saveGState()
    ctx.addPath(tongueClip)
    ctx.clip()
    ctx.translateBy(x: mouthCenter.x + 16, y: mouthCenter.y + 20)
    ctx.rotate(by: -0.16)
    // Long enough that its top sits up under the upper lip, where the clip hides it.
    let tongue = CGRect(x: -28, y: -40, width: 56, height: 96)
    let tonguePath = CGPath(roundedRect: tongue, cornerWidth: 28, cornerHeight: 28, transform: nil)
    ctx.addPath(tonguePath)
    ctx.setFillColor(color(0xFF6E8E))
    ctx.fillPath()
    // Darker where it leaves the mouth, for depth (confined to the tongue)
    ctx.addPath(tonguePath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([color(0x9E2447, 0.55), color(0x9E2447, 0)]),
                           start: CGPoint(x: 0, y: -10), end: CGPoint(x: 0, y: 24), options: [])
    ctx.setStrokeColor(color(0xD9446A))
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 0, y: 14))
    ctx.addLine(to: CGPoint(x: 0, y: 40))
    ctx.strokePath()
    ctx.restoreGState()
}

func drawTile(_ ctx: CGContext, _ tilePath: CGPath) {
    // Warm off-white tile
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 32, color: color(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0xF4F1EB))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xFFFEFB), color(0xE6E1D8)]),
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // Soft contact shadow under the octopus
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 812)
    ctx.scaleBy(x: 1, y: 0.13)
    ctx.drawRadialGradient(gradient([color(0x000000, 0.16), color(0x000000, 0)]),
                           startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 300, options: [])
    ctx.restoreGState()
    ctx.restoreGState()
}

/// When writing a single .png, draw just the octopus (no tile) for use as the in-app logo mark.
let markOnly = CommandLine.arguments.dropFirst().first?.hasSuffix(".png") ?? false

func drawIcon(_ ctx: CGContext) {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

    if !markOnly { drawTile(ctx, tilePath) }
    // Six visible arms in mirrored pairs, splaying out from under the head and curling outward at the tips.
    // Drawn outer pair first so the inner arms overlap them, then the head on top.
    let headCenter = CGPoint(x: 512, y: 392)
    let pairs: [(CGPoint, CGPoint, CGPoint, CGPoint, CGFloat)] = [
        // outer: sweeps out sideways and curls up
        (CGPoint(x: 400, y: 520), CGPoint(x: 330, y: 640), CGPoint(x: 200, y: 640), CGPoint(x: 206, y: 548), 74),
        // middle: down and out, curling up
        (CGPoint(x: 446, y: 548), CGPoint(x: 410, y: 690), CGPoint(x: 300, y: 770), CGPoint(x: 276, y: 692), 78),
        // inner: mostly down, a small outward curl
        (CGPoint(x: 486, y: 556), CGPoint(x: 476, y: 700), CGPoint(x: 420, y: 800), CGPoint(x: 380, y: 760), 80),
    ]
    for (p0, p1, p2, p3, width) in pairs {
        for mirrored in [false, true] {
            func m(_ p: CGPoint) -> CGPoint { mirrored ? CGPoint(x: 1024 - p.x, y: p.y) : p }
            drawArm(ctx, Arm(p0: m(p0), p1: m(p1), p2: m(p2), p3: m(p3), baseWidth: width, tipWidth: 11))
        }
    }
    drawHead(ctx, center: headCenter)
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = context.cgContext
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    // Work in a top-left-origin 1024 canvas.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: CGFloat(size) / 1024, y: -CGFloat(size) / 1024)
    drawIcon(ctx)
    ctx.flush()
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
if markOnly {
    // Square crop around the octopus, transparent background.
    let size = 512, crop = CGRect(x: 182, y: 186, width: 660, height: 660)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: CGFloat(size) / crop.width, y: -CGFloat(size) / crop.height)
    ctx.translateBy(x: -crop.minX, y: -crop.minY)
    drawIcon(ctx)
    try rep.representation(using: .png, properties: [:])!.write(to: output)
    print("Wrote \(output.path)")
    exit(0)
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: output.appending(path: "icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: output.appending(path: "icon_\(base)x\(base)@2x.png"))
}
print("Wrote \(output.path)")
