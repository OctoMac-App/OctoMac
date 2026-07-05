import SwiftUI

// OctoMac's visual language: "the build plate".
// Graphite/aluminium surfaces like a printer frame, the octopus's green for actions, heat colours for temperature,
// and a per-printer filament colour for identity. DIN for every number, Avenir Next for words.

enum Palette {
    static let graphite = Color(hex: 0x1C2026)    // window base
    static let rail = Color(hex: 0x191C21)        // printer rail
    static let extrusion = Color(hex: 0x262B33)   // raised surfaces
    static let extrusionHi = Color(hex: 0x2E343D) // hover / selected surfaces
    static let edge = Color(hex: 0x3A414C)        // hairlines, bevels, empty layers
    static let paper = Color(hex: 0xECE6D8)       // primary text
    static let dust = Color(hex: 0x9AA0A8)        // secondary text
    static let faint = Color(hex: 0x6B717A)       // tertiary text
    /// Brand and action colour: the octopus's green. Buttons, the selected tab, links, sliders.
    static let accent = Color(hex: 0x5CCB66)

    static let cold = Color(hex: 0x5EC8E5)
    static let warm = Color(hex: 0xF2C14E)
    static let hot = Color(hex: 0xF2545B)
    static let ready = Color(hex: 0x7CC59B)

    /// Filament colours handed out to printers in order; each printer can override.
    static let filaments: [Color] = [
        Color(hex: 0x8F7CFF), Color(hex: 0x4FD1C5), Color(hex: 0xF29E4C), Color(hex: 0xE86A92), Color(hex: 0x9BD15B),
    ]

    /// Maps a temperature to the cold → warm → hot ramp (room temp is cold, ~200°+ is hot).
    static func heat(_ celsius: Double?) -> Color {
        guard let celsius else { return faint }
        let t = max(0, min(1, (celsius - 30) / 190))
        return t < 0.5 ? cold.mix(with: warm, by: t * 2) : warm.mix(with: hot, by: (t - 0.5) * 2)
    }
}

enum Typeface {
    /// Numbers: DIN Alternate, engineering-standard and tabular enough for live readouts.
    static func number(_ size: CGFloat) -> Font { .custom("DINAlternate-Bold", size: size) }
    /// Condensed DIN for dense numeric captions.
    static func condensed(_ size: CGFloat) -> Font { .custom("DINCondensed-Bold", size: size) }

    static func text(_ size: CGFloat, _ weight: Weight = .regular) -> Font { .custom(weight.name, size: size) }

    enum Weight {
        case regular, medium, demibold, bold
        var name: String {
            switch self {
            case .regular: "AvenirNext-Regular"
            case .medium: "AvenirNext-Medium"
            case .demibold: "AvenirNext-DemiBold"
            case .bold: "AvenirNext-Bold"
            }
        }
    }

    // Scale (≈ 1.25 ratio from 13pt body)
    static let caption = text(11, .medium)
    static let body = text(13)
    static let bodyStrong = text(13, .demibold)
    static let subhead = text(16, .demibold)
    static let title = text(22, .demibold)
    static let display = text(30, .bold)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(hex: value)
    }

    var hexString: String? {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((components.redComponent * 255).rounded())
        let g = Int((components.greenComponent * 255).rounded())
        let b = Int((components.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Surfaces

/// A machined panel: extrusion fill with a 1px top bevel highlight. Radius encodes hierarchy
/// (stage panels 20, tiles 14, controls 10, chips are capsules).
struct Machined: ViewModifier {
    var radius: CGFloat = 14
    var fill: Color = Palette.extrusion

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.0), .black.opacity(0.25)],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 1
                            )
                    }
            }
    }
}

extension View {
    func machined(radius: CGFloat = 14, fill: Color = Palette.extrusion) -> some View {
        modifier(Machined(radius: radius, fill: fill))
    }
}

/// Faint horizontal layer lines across the window, like the side of a print.
struct LayerLineBackground: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(0.018)))
                y += 4
            }
        }
        .background(Palette.graphite)
        .ignoresSafeArea()
    }
}

/// A dark textured print sheet: graphite with a fine speckle and a faint green cast. Used where there's nothing else to show.
struct BuildPlateTexture: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x2B3330), Color(hex: 0x232A28), Color(hex: 0x1B2120)]),
                                               startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            var generator = SeededGenerator(seed: 42)
            let count = Int(size.width * size.height / 90)
            for _ in 0..<count {
                let x = CGFloat.random(in: 0..<size.width, using: &generator)
                let y = CGFloat.random(in: 0..<size.height, using: &generator)
                let light = Bool.random(using: &generator)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)),
                             with: .color(light ? .white.opacity(0.07) : .black.opacity(0.22)))
            }
        }
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Buttons

/// Primary action: accent-green capsule with dark text.
struct PlateButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        PlateButtonBody(configuration: configuration, tint: tint, prominent: prominent)
    }

    private struct PlateButtonBody: View {
        let configuration: Configuration
        let tint: Color
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Typeface.bodyStrong)
                .foregroundStyle(prominent ? Palette.graphite : Palette.paper)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(prominent ? tint : (hovering ? Palette.extrusionHi : Palette.extrusion))
                    if !prominent { Capsule().strokeBorder(Palette.edge, lineWidth: 1) }
                }
                .brightness(configuration.isPressed ? -0.08 : (hovering && prominent ? 0.05 : 0))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }
    }
}

/// Square-ish control used on the jog pad and quick actions.
struct KeyButtonStyle: ButtonStyle {
    var size: CGSize = CGSize(width: 52, height: 52)

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration, size: size)
    }

    private struct KeyBody: View {
        let configuration: Configuration
        let size: CGSize
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(hovering ? Palette.accent : Palette.paper)
                .frame(width: size.width, height: size.height)
                .machined(radius: 10, fill: configuration.isPressed ? Palette.edge : (hovering ? Palette.extrusionHi : Palette.extrusion))
                .opacity(isEnabled ? 1 : 0.35)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == PlateButtonStyle {
    static var plate: PlateButtonStyle { PlateButtonStyle() }
    static var plateQuiet: PlateButtonStyle { PlateButtonStyle(prominent: false) }
    static func plate(_ tint: Color) -> PlateButtonStyle { PlateButtonStyle(tint: tint) }
}

extension ButtonStyle where Self == KeyButtonStyle {
    static var key: KeyButtonStyle { KeyButtonStyle() }
}

/// A selectable capsule chip (step sizes, filters).
struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typeface.number(13))
                .foregroundStyle(selected ? Palette.graphite : Palette.dust)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Palette.accent : Palette.extrusion))
                .overlay(Capsule().strokeBorder(selected ? .clear : Palette.edge, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Dark text field matching the theme.
struct PlateField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Typeface.body)
            .foregroundStyle(Palette.paper)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.graphite))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.edge, lineWidth: 1))
    }
}

extension View {
    func plateField() -> some View { modifier(PlateField()) }
}

/// Small section heading used inside panels — sentence case, quiet.
struct PanelHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Typeface.subhead).foregroundStyle(Palette.paper)
            Spacer()
            if let detail { Text(detail).font(Typeface.caption).foregroundStyle(Palette.dust) }
        }
    }
}
