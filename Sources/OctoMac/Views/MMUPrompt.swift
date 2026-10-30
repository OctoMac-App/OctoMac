import OctoPrintKit
import SwiftUI

/// The Prusa MMU plugin's "which filament?" question, shown over the whole window because the print is waiting.
struct MMUPromptOverlay: View {
    let session: PrinterSession
    let settings: PrusaMMU.Settings
    let since: Date
    @State private var dismissed = false

    var body: some View {
        if !dismissed {
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(Palette.accent.opacity(0.15)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Which filament?").font(Typeface.title).foregroundStyle(Palette.paper)
                            Text("\(session.instance.name) is waiting to start \(jobName)")
                                .font(Typeface.body).foregroundStyle(Palette.dust).lineLimit(1)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
                        ForEach(settings.filaments) { filament in
                            FilamentChoice(number: settings.number(for: filament), label: settings.label(for: filament),
                                           color: filament.color.flatMap(Color.init(hexString:)),
                                           loaded: session.mmuTool == filament.index) {
                                session.chooseMMUFilament(filament.index)
                            }
                        }
                    }

                    Countdown(since: since, duration: settings.timeout)

                    HStack(spacing: 10) {
                        Text(session.mmuCanSkip
                             ? "If you don't choose, the print uses the filament it was sliced with."
                             : "If you don't choose, the printer will ask on its own screen.")
                            .font(Typeface.caption).foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if session.mmuCanSkip {
                            Button("Use sliced filament") { session.chooseMMUFilament(nil) }
                                .buttonStyle(.plateQuiet)
                        } else {
                            Button("Choose on the printer") { dismissed = true }
                                .buttonStyle(.plateQuiet)
                                .keyboardShortcut(.cancelAction)
                        }
                    }
                }
                .padding(28)
                .frame(width: 660)
                .machined(radius: 22, fill: Palette.extrusion)
                .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
            }
            .transition(.opacity)
        }
    }

    private var jobName: String {
        guard let name = session.job?.file.displayName else { return String(localized: "a print") }
        return SlicedName(name).title
    }
}

struct FilamentChoice: View {
    let number: Int
    let label: String
    let color: Color?
    let loaded: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(color ?? Palette.graphite)
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    Text(verbatim: "\(number)")
                        .font(Typeface.number(15))
                        .foregroundStyle(color.map { $0.isLight ? Color.black.opacity(0.75) : Color.white } ?? Palette.paper)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(2)
                    if loaded { Text("Loaded now").font(Typeface.caption).foregroundStyle(Palette.accent) }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hovering ? Palette.extrusionHi : Palette.graphite))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(hovering ? Palette.accent : Palette.edge, lineWidth: hovering ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut(KeyEquivalent(Character(String(min(9, number)))), modifiers: [])
        .help("Print with \(label) (press \(min(9, number)))")
    }
}

/// A draining bar showing how long until the plugin stops waiting.
struct Countdown: View {
    let since: Date
    let duration: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            let left = max(0, duration - timeline.date.timeIntervalSince(since))
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.graphite)
                        Capsule().fill(left < 8 ? Palette.warm : Palette.accent)
                            .frame(width: geo.size.width * left / max(1, duration))
                    }
                }
                .frame(height: 6)
                Text(left > 0 ? "\(Int(left.rounded(.up))) seconds left to choose" : "Time's up")
                    .font(Typeface.caption).foregroundStyle(left < 8 ? Palette.warm : Palette.dust)
            }
        }
    }
}

extension Color {
    /// Rough perceived brightness, for choosing readable text on a swatch.
    var isLight: Bool {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return false }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.6
    }
}

/// A question from the printer's firmware, such as "Filament runout. Continue?", shown over the whole window because
/// the printer is waiting. The answer goes back to the printer, just like pressing the button on its screen.
struct PrinterPromptOverlay: View {
    let session: PrinterSession
    let prompt: ActionPrompt.Prompt
    @State private var dismissed = false

    var body: some View {
        if !dismissed {
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        Image(systemName: "questionmark.bubble.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Palette.warm)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(Palette.warm.opacity(0.15)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(session.instance.name) is asking").font(Typeface.caption).foregroundStyle(Palette.faint)
                            Text(verbatim: prompt.text).font(Typeface.title).foregroundStyle(Palette.paper)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if prompt.choices.isEmpty {
                        Text("The printer didn't offer any answers. Carry on from its own screen.")
                            .font(Typeface.body).foregroundStyle(Palette.dust)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                            ForEach(Array(prompt.choices.enumerated()), id: \.offset) { index, choice in
                                Button { session.answerPrinterPrompt(index) } label: {
                                    Text(verbatim: choice)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(index == 0 ? .plate : .plateQuiet)
                                .controlSize(.large)
                                .keyboardShortcut(index == 0 ? .defaultAction : KeyboardShortcut(KeyEquivalent(Character(String(min(9, index + 1)))), modifiers: []))
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Text("The printer is waiting. Your answer is sent to it straight away.")
                            .font(Typeface.caption).foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Answer on the printer") { dismissed = true }
                            .buttonStyle(.plateQuiet)
                            .keyboardShortcut(.cancelAction)
                    }
                }
                .padding(28)
                .frame(width: 560)
                .machined(radius: 22, fill: Palette.extrusion)
                .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
            }
            .transition(.opacity)
        }
    }
}
