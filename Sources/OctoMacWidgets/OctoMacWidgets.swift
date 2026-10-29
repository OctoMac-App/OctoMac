import AppIntents
import SwiftUI
import WidgetData
import WidgetKit

@main
struct OctoMacWidgetBundle: WidgetBundle {
    var body: some Widget {
        PrintersWidget()
        if #available(macOS 26.0, *) {
            PrinterControl()
        }
    }
}

// MARK: - Timeline

struct PrintersEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct PrintersProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrintersEntry { PrintersEntry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (PrintersEntry) -> Void) {
        completion(PrintersEntry(date: .now, snapshot: context.isPreview ? (WidgetSnapshot.load() ?? .sample) : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrintersEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        WidgetLanguage.follow(snapshot)
        // While something prints, step the progress forward every two minutes; OctoMac also refreshes the widgets
        // whenever a printer changes.
        let printing = snapshot?.printers.contains { $0.status == .printing } ?? false
        let dates = printing ? (0..<30).map { Date.now.addingTimeInterval(Double($0) * 120) } : [Date.now]
        let refresh = Date.now.addingTimeInterval(printing ? 3600 : 1800)
        completion(Timeline(entries: dates.map { PrintersEntry(date: $0, snapshot: snapshot) }, policy: .after(refresh)))
    }
}

// MARK: - Widget

struct PrintersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OctoMacPrinters", provider: PrintersProvider()) { entry in
            PrintersWidgetView(entry: entry)
                .containerBackground(Theme.graphite, for: .widget)
                .environment(\.locale, entry.snapshot?.language.map(Locale.init(identifier:)) ?? .current)
        }
        .configurationDisplayName("Printers")
        .description("Your printers' progress, time left and temperatures.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PrintersWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PrintersEntry

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.printers.isEmpty {
            switch family {
            case .systemSmall: SmallView(snapshot: snapshot, date: entry.date)
            case .systemLarge: LargeView(snapshot: snapshot, date: entry.date)
            default: ListView(snapshot: snapshot, date: entry.date, limit: 3)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "printer").font(.title2).foregroundStyle(Theme.accent)
                Text("Open OctoMac to see your printers here.")
                    .font(.caption).foregroundStyle(Theme.dust).multilineTextAlignment(.center)
            }
        }
    }
}

private struct SmallView: View {
    let snapshot: WidgetSnapshot
    let date: Date

    var body: some View {
        let printer = snapshot.featured!
        let (progress, left) = printer.projected(to: date, from: snapshot.written)
        VStack(alignment: .leading, spacing: 6) {
            PrinterTitle(printer: printer)
            Spacer(minLength: 0)
            if printer.status == .printing || printer.status == .paused, let progress {
                Text("\(Int(progress * 100))%").font(.custom("DIN Alternate", size: 40).weight(.bold)).foregroundStyle(Theme.paper)
                    .contentTransition(.numericText())
                ProgressBar(value: progress, tint: printer.tint)
                Text(left.map { String(localized: "\(Format.duration($0)) left") } ?? printer.statusText)
                    .font(.custom("Avenir Next", size: 11).weight(.medium)).foregroundStyle(Theme.dust).lineLimit(1)
            } else {
                Text(printer.statusText).font(.custom("Avenir Next", size: 15).weight(.semibold)).foregroundStyle(Theme.paper).lineLimit(2)
                Temperatures(printer: printer, unit: snapshot.temperatureUnit)
            }
        }
        .background(alignment: .center) {
            CameraBackdrop(printer: printer).padding(-16)
        }
    }
}

private struct ListView: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(snapshot.printers.prefix(limit)) { printer in
                PrinterRow(printer: printer, snapshot: snapshot, date: date)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct LargeView: View {
    let snapshot: WidgetSnapshot
    let date: Date

    var body: some View {
        let printer = snapshot.featured!
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                Camera(printer: printer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(printer.name).font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.5)))
                    .padding(8)
            }
            ListView(snapshot: snapshot, date: date, limit: 4)
        }
    }
}

private struct PrinterRow: View {
    let printer: WidgetSnapshot.Printer
    let snapshot: WidgetSnapshot
    let date: Date

    var body: some View {
        let (progress, left) = printer.projected(to: date, from: snapshot.written)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                PrinterTitle(printer: printer)
                Spacer(minLength: 6)
                if let progress, printer.status == .printing || printer.status == .paused {
                    Text("\(Int(progress * 100))%").font(.custom("DIN Alternate", size: 16).weight(.bold)).foregroundStyle(Theme.paper)
                }
            }
            if let progress, printer.status == .printing || printer.status == .paused {
                ProgressBar(value: progress, tint: printer.tint)
                HStack {
                    Text(printer.job ?? printer.statusText).lineLimit(1)
                    Spacer(minLength: 6)
                    if let left { Text("\(Format.duration(left)) left").lineLimit(1) }
                }
                .font(.custom("Avenir Next", size: 11).weight(.medium)).foregroundStyle(Theme.dust)
            } else {
                HStack {
                    Text(printer.statusText).lineLimit(1)
                    Spacer(minLength: 6)
                    Temperatures(printer: printer, unit: snapshot.temperatureUnit)
                }
                .font(.custom("Avenir Next", size: 11).weight(.medium)).foregroundStyle(Theme.dust)
            }
        }
    }
}

private struct PrinterTitle: View {
    let printer: WidgetSnapshot.Printer

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(printer.statusColor).frame(width: 7, height: 7)
            Text(printer.name).font(.custom("Avenir Next", size: 12).weight(.semibold)).foregroundStyle(Theme.paper).lineLimit(1)
        }
    }
}

private struct Temperatures: View {
    let printer: WidgetSnapshot.Printer
    let unit: String

    var body: some View {
        HStack(spacing: 8) {
            if let hotend = printer.hotend { Label(Format.temp(hotend, unit), systemImage: "flame").labelStyle(.titleAndIcon) }
            if let bed = printer.bed { Label(Format.temp(bed, unit), systemImage: "square.3.layers.3d.bottom.filled").labelStyle(.titleAndIcon) }
        }
        .font(.custom("Avenir Next", size: 11).weight(.medium)).foregroundStyle(Theme.dust)
    }
}

private struct ProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.edge)
                Capsule().fill(tint).frame(width: max(4, geo.size.width * value))
            }
        }
        .frame(height: 5)
    }
}

private struct Camera: View {
    let printer: WidgetSnapshot.Printer

    var body: some View {
        if printer.hasCamera, let image = NSImage(contentsOf: WidgetSnapshot.cameraURL(for: printer.id)) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Theme.extrusion
                Image(systemName: "web.camera").font(.title).foregroundStyle(Theme.dust)
            }
        }
    }
}

/// A dimmed camera picture behind the small widget.
private struct CameraBackdrop: View {
    let printer: WidgetSnapshot.Printer

    var body: some View {
        if printer.hasCamera, let image = NSImage(contentsOf: WidgetSnapshot.cameraURL(for: printer.id)) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .overlay(LinearGradient(colors: [Theme.graphite.opacity(0.55), Theme.graphite.opacity(0.95)], startPoint: .top, endPoint: .bottom))
        }
    }
}

// MARK: - Control Centre

@available(macOS 26.0, *)
struct PrinterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "OctoMacPrinterControl", provider: ControlStatusProvider()) { status in
            ControlWidgetButton(action: OpenOctoMac()) {
                Label(status.title, systemImage: status.symbol)
                Text(status.detail)
            }
        }
        .displayName("OctoMac")
        .description("Shows how your print is going. Click to open OctoMac.")
    }
}

@available(macOS 26.0, *)
struct ControlStatus {
    var title: String
    var detail: String
    var symbol: String
}

@available(macOS 26.0, *)
struct ControlStatusProvider: ControlValueProvider {
    var previewValue: ControlStatus {
        ControlStatus(title: "Workshop MK3S", detail: String(localized: "\(0.64.formatted(.percent)), \(Format.duration(4680)) left"), symbol: "printer.fill")
    }

    func currentValue() async throws -> ControlStatus {
        guard let snapshot = WidgetSnapshot.load(), let printer = snapshot.featured else {
            return ControlStatus(title: "OctoMac", detail: String(localized: "Open OctoMac"), symbol: "printer")
        }
        let (progress, left) = printer.projected(to: .now, from: snapshot.written)
        switch printer.status {
        case .printing, .paused:
            let percent = progress.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? printer.statusText
            let detail = switch (printer.status == .paused, left) {
            case (true, let left?): String(localized: "Paused, \(percent), \(Format.duration(left)) left")
            case (true, nil): String(localized: "Paused, \(percent)")
            case (false, let left?): String(localized: "\(percent), \(Format.duration(left)) left")
            case (false, nil): percent
            }
            return ControlStatus(title: printer.name, detail: detail, symbol: printer.status == .paused ? "pause.circle" : "printer.fill")
        default:
            return ControlStatus(title: printer.name, detail: printer.statusText, symbol: "printer")
        }
    }
}

/// Opens OctoMac (the app that contains this widget).
struct OpenOctoMac: AppIntent {
    static let title: LocalizedStringResource = "Open OctoMac"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}

/// The widgets show OctoMac's language, not necessarily the Mac's. Text in views follows the locale in their
/// environment straight away; text made in code follows the extension's own language, which takes effect the next
/// time macOS starts the extension.
enum WidgetLanguage {
    static func follow(_ snapshot: WidgetSnapshot?) {
        guard let language = snapshot?.language else { return }
        if (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first != language {
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
        }
    }
}

// MARK: - Look

enum Theme {
    static let graphite = Color(red: 0x1C / 255, green: 0x20 / 255, blue: 0x26 / 255)
    static let extrusion = Color(red: 0x26 / 255, green: 0x2B / 255, blue: 0x33 / 255)
    static let edge = Color(red: 0x3A / 255, green: 0x41 / 255, blue: 0x4C / 255)
    static let paper = Color(red: 0xEC / 255, green: 0xE6 / 255, blue: 0xD8 / 255)
    static let dust = Color(red: 0x9A / 255, green: 0xA0 / 255, blue: 0xA8 / 255)
    static let accent = Color(red: 0x5C / 255, green: 0xCB / 255, blue: 0x66 / 255)
    static let warm = Color(red: 0xF2 / 255, green: 0xC1 / 255, blue: 0x4E / 255)
    static let hot = Color(red: 0xF2 / 255, green: 0x54 / 255, blue: 0x5B / 255)
}

extension WidgetSnapshot.Printer {
    var tint: Color {
        guard let hex = colorHex?.trimmingCharacters(in: CharacterSet(charactersIn: "#")), let value = UInt32(hex, radix: 16) else { return Theme.accent }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    var statusColor: Color {
        switch status {
        case .printing: tint
        case .paused: Theme.warm
        case .ready: Theme.accent
        case .offline: Theme.dust
        case .problem: Theme.hot
        }
    }
}

enum Format {
    static func duration(_ seconds: Double) -> String {
        if seconds < 60 { return String(localized: "<1 min") }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    static func temp(_ celsius: Double, _ unit: String) -> String {
        let value = unit == "fahrenheit" ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(written: .now, printers: [
        .init(id: UUID(), name: "Workshop MK3S", colorHex: "#8F7CFF", status: .printing, statusText: "Printing", job: "gridfinity bins 3x2",
              progress: 0.64, timeLeft: 4680, hotend: 215, hotendTarget: 215, bed: 60, bedTarget: 60, hasCamera: false),
        .init(id: UUID(), name: "Studio Ender", colorHex: "#4FD1C5", status: .ready, statusText: "Ready", job: nil,
              progress: nil, timeLeft: nil, hotend: 24, hotendTarget: 0, bed: 23, bedTarget: 0, hasCamera: false),
    ], temperatureUnit: "celsius")
}
