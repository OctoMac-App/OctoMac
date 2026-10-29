import AppKit
import Charts
import OctoPrintKit
import SwiftUI
import UniformTypeIdentifiers

typealias SeriesPoint = (point: TemperaturePoint, series: String)

/// Everything the temperature chart draws, computed once from the session so the live chart, the PNG export and
/// the SVG export all show the same thing.
struct ChartData {
    let heaterPoints: [TemperaturePoint]
    let actual: [SeriesPoint]
    let target: [SeriesPoint]
    let events: [ChartEvent]
    let yMax: Double
    let seriesNames: [String]

    @MainActor
    init(session: PrinterSession) {
        heaterPoints = session.temperatureHistory.filter { HeaterKind(key: $0.heater).isHeater }
        actual = Self.drawable(Self.segments(heaterPoints) { $0.actual != nil }.map { ($0.point, "actual-" + $0.series) })
        target = Self.drawable(Self.segments(heaterPoints) { ($0.target ?? 0) > 0 }.map { ($0.point, "target-" + $0.series) }, minimumSpan: 10)
        let first = heaterPoints.first?.time
        events = first.map { first in session.chartEvents.filter { $0.time >= first } } ?? []
        // Keep at least 0–60° on screen so ambient wobble doesn't look like a heating event, and base the scale only
        // on what's drawn so a target that flickered on for a moment can't stretch it.
        let peak = max(actual.compactMap(\.point.actual).max() ?? 0, target.compactMap(\.point.target).max() ?? 0)
        yMax = max(60, (peak * 1.1 / 25).rounded(.up) * 25)
        seriesNames = Set(heaterPoints.filter { $0.actual != nil }.map(\.heater)).sorted().map { HeaterKind(key: $0).displayName }
    }

    var isEmpty: Bool { heaterPoints.isEmpty }

    var timeRange: ClosedRange<Date>? {
        guard let first = heaterPoints.first?.time, let last = heaterPoints.last?.time, first < last else { return nil }
        return first...last
    }

    /// Each heater's nearest reading to `time`, plus any event close by.
    func readout(at time: Date) -> HoverReadout? {
        guard !heaterPoints.isEmpty else { return nil }
        let values = Dictionary(grouping: heaterPoints, by: \.heater).values.compactMap { points in
            points.filter { $0.actual != nil }
                .min { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }
        }
        .filter { abs($0.time.timeIntervalSince(time)) < 30 } // no reading nearby (e.g. a disconnect gap)
        .sorted { $0.heater > $1.heater } // hotend before bed
        // Events within ~1% of the visible span count as "here".
        let span = timeRange.map { $0.upperBound.timeIntervalSince($0.lowerBound) } ?? 0
        let nearby = events.filter { abs($0.time.timeIntervalSince(time)) < max(10, span * 0.01) }
        guard !values.isEmpty || !nearby.isEmpty else { return nil }
        return HoverReadout(time: values.first?.time ?? time, values: values, events: nearby)
    }

    static func eventColor(_ kind: ChartEvent.Kind) -> Color {
        switch kind {
        case .started, .done, .resumed: Palette.ready
        case .cancelled, .failed, .error: Palette.hot
        case .paused: Palette.warm
        case .connected, .disconnected: Palette.dust
        }
    }

    /// Splits each heater's readings into separate series wherever `include` is false or readings stop for a while,
    /// so the chart never draws a line bridging two unrelated stretches.
    private static func segments(_ points: [TemperaturePoint], _ include: (TemperaturePoint) -> Bool) -> [SeriesPoint] {
        var result: [SeriesPoint] = []
        for (heater, heaterPoints) in Dictionary(grouping: points, by: \.heater) {
            var segment = 0
            var previous: Date?
            var inRun = false
            for point in heaterPoints.sorted(by: { $0.time < $1.time }) {
                guard include(point) else { inRun = false; continue }
                if !inRun || (previous.map { point.time.timeIntervalSince($0) > 30 } ?? false) { segment += 1 }
                inRun = true
                previous = point.time
                result.append((point, "\(heater)#\(segment)"))
            }
        }
        return result
    }

    /// Drops segments too short to read: single readings render as stray dots, and a target that was on for a
    /// moment (a preset immediately followed by cool down) is noise that would also stretch the scale.
    private static func drawable(_ items: [SeriesPoint], minimumSpan: TimeInterval = 0) -> [SeriesPoint] {
        let spans = Dictionary(grouping: items, by: \.series).mapValues { group -> (count: Int, span: TimeInterval) in
            let times = group.map(\.point.time)
            return (group.count, (times.max() ?? .now).timeIntervalSince(times.min() ?? .now))
        }
        return items.filter { item in
            guard let info = spans[item.series] else { return false }
            return info.count > 1 && info.span >= minimumSpan
        }
    }
}

/// What the chart shows under the mouse: each heater's nearest reading and any event close by.
struct HoverReadout {
    let time: Date
    let values: [TemperaturePoint]
    let events: [ChartEvent]
}

// MARK: - Panel

struct TemperaturePanel: View {
    let session: PrinterSession
    @State private var hoverTime: Date?

    var body: some View {
        let data = ChartData(session: session)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 6) {
                Text("Last 30 minutes").font(Typeface.subhead).foregroundStyle(Palette.paper)
                ChartExportMenu(session: session, data: data)
                Spacer()
                CurrentReadings(session: session)
            }
            TemperatureChart(data: data, hoverTime: $hoverTime)
                .overlay {
                    if data.isEmpty {
                        Text("Waiting for temperature readings").font(Typeface.body).foregroundStyle(Palette.dust)
                    }
                }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .machined(radius: 20)
    }
}

/// The chart itself. Pass `hoverTime` for the interactive version; leave it nil when rendering for export.
struct TemperatureChart: View {
    /// Grid lines at round numbers in the unit being shown (0, 50, 100°C or 50, 100, 150°F…), as Celsius positions.
    nonisolated static func temperatureTicks(upTo maxCelsius: Double) -> [Double] {
        let unit = TemperatureUnit.current
        let top = unit.convert(maxCelsius), bottom = unit.convert(0)
        let step: Double = unit == .celsius ? (maxCelsius <= 100 ? 20 : 50) : (top <= 250 ? 50 : 100)
        var ticks: [Double] = []
        var value = (bottom / step).rounded(.up) * step
        if unit == .celsius { value = 0 }
        while value <= top + 0.1 {
            ticks.append(unit == .celsius ? value : (value - 32) * 5 / 9)
            value += step
        }
        return ticks
    }

    let data: ChartData
    var hoverTime: Binding<Date?>?

    var body: some View {
        let hover = hoverTime?.wrappedValue.flatMap(data.readout(at:))
        Chart {
            ForEach(data.actual, id: \.point.id) { item in
                AreaMark(x: .value("Time", item.point.time), yStart: .value("Base", 0), yEnd: .value("°C", item.point.actual ?? 0),
                         series: .value("Series", item.series))
                    .foregroundStyle(by: .value("Heater", HeaterKind(key: item.point.heater).displayName))
                    .opacity(0.07)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", item.point.time), y: .value("°C", item.point.actual ?? 0), series: .value("Series", item.series))
                    .foregroundStyle(by: .value("Heater", HeaterKind(key: item.point.heater).displayName))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            // Targets change instantly, so they're drawn as steps, one series per stretch where a target was set.
            ForEach(data.target, id: \.point.id) { item in
                LineMark(x: .value("Time", item.point.time), y: .value("°C", item.point.target ?? 0), series: .value("Series", item.series))
                    .foregroundStyle(by: .value("Heater", HeaterKind(key: item.point.heater).displayName))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                    .interpolationMethod(.stepEnd)
                    .opacity(0.7)
            }

            ForEach(data.events) { event in
                RuleMark(x: .value("Time", event.time))
                    .foregroundStyle(ChartData.eventColor(event.kind).opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .annotation(position: .top, alignment: .leading, spacing: 2,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        EventFlag(kind: event.kind, color: ChartData.eventColor(event.kind))
                    }
            }

            if let hover {
                RuleMark(x: .value("Time", hover.time))
                    .foregroundStyle(Palette.paper.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        ChartTooltip(readout: hover)
                    }
                ForEach(hover.values, id: \.heater) { value in
                    if let actual = value.actual {
                        PointMark(x: .value("Time", value.time), y: .value("°C", actual))
                            .foregroundStyle(seriesColor(HeaterKind(key: value.heater).displayName))
                            .symbolSize(60)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            if let hoverTime {
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plot = proxy.plotFrame else { return }
                                hoverTime.wrappedValue = proxy.value(atX: location.x - geo[plot].origin.x, as: Date.self)
                            case .ended:
                                hoverTime.wrappedValue = nil
                            }
                        }
                }
            }
        }
        .chartForegroundStyleScale(domain: data.seriesNames, range: data.seriesNames.map(seriesColor))
        .chartYScale(domain: 0...data.yMax)
        .padding(.top, data.events.isEmpty ? 0 : 22) // headroom for event flags above the plot
        .chartLegend(.hidden) // the live readings in the header double as the legend
        .chartYAxis {
            AxisMarks(position: .leading, values: TemperatureChart.temperatureTicks(upTo: data.yMax)) { value in
                AxisGridLine().foregroundStyle(Palette.edge.opacity(0.6))
                AxisValueLabel {
                    if let celsius = value.as(Double.self) { Text(Fmt.deg(celsius)).font(Typeface.number(11)).foregroundStyle(Palette.faint) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        // With only a few minutes of history, ticks are closer than a minute apart.
                        let short = (data.timeRange.map { $0.upperBound.timeIntervalSince($0.lowerBound) } ?? 0) < 6 * 60
                        Text(date, format: short ? .dateTime.hour().minute().second() : .dateTime.hour().minute())
                            .font(Typeface.number(11)).foregroundStyle(Palette.faint)
                    }
                }
            }
        }
    }
}

// MARK: - Quiet menu trigger

/// A minimal dropdown trigger: an icon and a small chevron that only brighten on hover.
struct QuietMenuLabel: View {
    let symbol: String
    var onDark = false
    /// Off for a plain button that looks the same.
    var chevron = true
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            if chevron { Image(systemName: "chevron.down").font(.system(size: 7, weight: .heavy)) }
        }
        .foregroundStyle(onDark ? .white.opacity(hovering ? 1 : 0.8) : (hovering ? Palette.paper : Palette.faint))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(onDark ? .black.opacity(hovering ? 0.65 : 0.45) : (hovering ? Palette.extrusionHi : .clear)))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
    }
}

extension View {
    /// Styles a `Menu` so only its custom label shows (no system bezel or indicator).
    func quietMenu() -> some View {
        menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}

// MARK: - Export

struct ChartExportMenu: View {
    let session: PrinterSession
    let data: ChartData

    var body: some View {
        AppMenu(items: [
            .action(String(localized: "Export as PNG…"), symbol: "photo") { export(.png) },
            .action(String(localized: "Export as SVG…"), symbol: "square.on.square") { export(.svg) },
        ]) {
            QuietMenuLabel(symbol: "square.and.arrow.down")
        }
        .help("Export this chart")
        .disabled(data.isEmpty)
    }

    private enum Format { case png, svg }

    private func export(_ format: Format) {
        let title = session.instance.name
        let subtitle = ChartExport.subtitle(for: data)
        let stamp = Date.now.formatted(.iso8601.year().month().day()) + " " + Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        let base = String(localized: "\(title) temperatures \(stamp)").replacingOccurrences(of: ":", with: ".")
        switch format {
        case .png:
            guard let png = ChartExport.png(data: data, title: title, subtitle: subtitle) else {
                session.error = ErrorBanner(message: String(localized: "Couldn't render the chart as an image."))
                return
            }
            SaveFile.present(data: png, name: base + ".png", type: .png)
        case .svg:
            let svg = ChartExport.svg(data: data, title: title, subtitle: subtitle)
            SaveFile.present(data: Data(svg.utf8), name: base + ".svg", type: .svg)
        }
    }
}

enum SaveFile {
    @MainActor
    static func present(data: Data, name: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        // Only constrain to types macOS knows. For others (e.g. .gcode) the panel would append its own extension
        // to a name that already has one, saving "part.gcode.gcode".
        if !type.isDynamic {
            panel.allowedContentTypes = [type]
        }
        panel.allowsOtherFileTypes = true
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }
}

enum ChartExport {
    static let size = CGSize(width: 1600, height: 800)

    static func subtitle(for data: ChartData) -> String {
        guard let range = data.timeRange else { return String(localized: "Temperatures") }
        let day = range.upperBound.formatted(date: .abbreviated, time: .omitted)
        let from = range.lowerBound.formatted(date: .omitted, time: .shortened)
        let to = range.upperBound.formatted(date: .omitted, time: .shortened)
        return String(localized: "Temperatures, \(from) to \(to), \(day)")
    }

    /// Renders the same SwiftUI chart used on screen, at 2× for a crisp image.
    @MainActor
    static func png(data: ChartData, title: String, subtitle: String) -> Data? {
        let card = VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Typeface.title).foregroundStyle(Palette.paper)
                    Text(subtitle).font(Typeface.body).foregroundStyle(Palette.dust)
                }
                Spacer()
                HStack(spacing: 18) {
                    ForEach(data.seriesNames, id: \.self) { name in
                        HStack(spacing: 6) {
                            Circle().fill(seriesColor(name)).frame(width: 9, height: 9)
                            Text(name).font(Typeface.body).foregroundStyle(Palette.dust)
                        }
                    }
                }
            }
            TemperatureChart(data: data, hoverTime: nil)
        }
        .padding(40)
        .frame(width: size.width, height: size.height)
        .background(Palette.extrusion)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    /// A hand-built SVG: real paths for each line, so it stays sharp and editable in any vector app.
    static func svg(data: ChartData, title: String, subtitle: String) -> String {
        let width = size.width, height = size.height
        let left = 80.0, right = 40.0, top = data.events.isEmpty ? 120.0 : 145.0, bottom = 70.0
        let plotW = width - left - right, plotH = height - top - bottom
        guard let range = data.timeRange else { return "" }
        let t0 = range.lowerBound.timeIntervalSince1970
        let span = max(1, range.upperBound.timeIntervalSince1970 - t0)
        func x(_ date: Date) -> Double { left + (date.timeIntervalSince1970 - t0) / span * plotW }
        func y(_ value: Double) -> Double { top + plotH - value / data.yMax * plotH }
        func f(_ value: Double) -> String { String(format: "%.1f", value) }
        func hex(_ color: Color) -> String { color.hexString ?? "#999999" }
        func esc(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let font = "font-family=\"Avenir Next, Helvetica Neue, Helvetica, Arial, sans-serif\""
        let numberFont = "font-family=\"DIN Alternate, Avenir Next, Helvetica, Arial, sans-serif\""

        var out: [String] = []
        out.append("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(Int(width))\" height=\"\(Int(height))\" viewBox=\"0 0 \(Int(width)) \(Int(height))\">")
        out.append("<rect x=\"0\" y=\"0\" width=\"\(Int(width))\" height=\"\(Int(height))\" rx=\"24\" fill=\"\(hex(Palette.extrusion))\"/>")
        out.append("<text x=\"\(Int(left - 40))\" y=\"62\" \(font) font-size=\"30\" font-weight=\"600\" fill=\"\(hex(Palette.paper))\">\(esc(title))</text>")
        out.append("<text x=\"\(Int(left - 40))\" y=\"94\" \(font) font-size=\"17\" fill=\"\(hex(Palette.dust))\">\(esc(subtitle))</text>")

        // Legend
        var legendX = width - right
        for name in data.seriesNames.reversed() {
            let textWidth = Double(name.count) * 9 + 8
            legendX -= textWidth + 22
            out.append("<circle cx=\"\(f(legendX))\" cy=\"72\" r=\"6\" fill=\"\(hex(seriesColor(name)))\"/>")
            out.append("<text x=\"\(f(legendX + 12))\" y=\"78\" \(font) font-size=\"17\" fill=\"\(hex(Palette.dust))\">\(esc(name))</text>")
        }

        // Y grid and labels
        for value in TemperatureChart.temperatureTicks(upTo: data.yMax) {
            out.append("<line x1=\"\(f(left))\" y1=\"\(f(y(value)))\" x2=\"\(f(width - right))\" y2=\"\(f(y(value)))\" stroke=\"\(hex(Palette.edge))\" stroke-width=\"1\"/>")
            out.append("<text x=\"\(f(left - 12))\" y=\"\(f(y(value) + 5))\" text-anchor=\"end\" \(numberFont) font-size=\"14\" fill=\"\(hex(Palette.faint))\">\(Fmt.deg(value))</text>")
        }

        // X labels every 5 minutes
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        var tick = (t0 / 300).rounded(.up) * 300
        while tick <= t0 + span {
            let date = Date(timeIntervalSince1970: tick)
            out.append("<text x=\"\(f(x(date)))\" y=\"\(f(top + plotH + 30))\" text-anchor=\"middle\" \(numberFont) font-size=\"14\" fill=\"\(hex(Palette.faint))\">\(formatter.string(from: date))</text>")
            tick += 300
        }

        // Actual temperatures: soft area plus a solid line per segment
        for (series, items) in Dictionary(grouping: data.actual, by: \.series).sorted(by: { $0.key < $1.key }) {
            let points = items.map(\.point).sorted { $0.time < $1.time }
            guard let first = points.first, let last = points.last else { continue }
            let color = hex(seriesColor(HeaterKind(key: first.heater).displayName))
            let line = points.map { "\(f(x($0.time))),\(f(y($0.actual ?? 0)))" }.joined(separator: " L")
            out.append("<path d=\"M\(f(x(first.time))),\(f(y(0))) L\(line) L\(f(x(last.time))),\(f(y(0))) Z\" fill=\"\(color)\" fill-opacity=\"0.08\" stroke=\"none\"/>")
            out.append("<path id=\"\(esc(series))\" d=\"M\(line)\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"2.5\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>")
        }

        // Targets as dashed steps
        for (_, items) in Dictionary(grouping: data.target, by: \.series).sorted(by: { $0.key < $1.key }) {
            let points = items.map(\.point).sorted { $0.time < $1.time }
            guard let first = points.first else { continue }
            var d = "M\(f(x(first.time))),\(f(y(first.target ?? 0)))"
            var previous = first.target ?? 0
            for point in points.dropFirst() {
                let target = point.target ?? 0
                d += " L\(f(x(point.time))),\(f(y(previous))) L\(f(x(point.time))),\(f(y(target)))"
                previous = target
            }
            let color = hex(seriesColor(HeaterKind(key: first.heater).displayName))
            out.append("<path d=\"\(d)\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"1.5\" stroke-dasharray=\"8 4\" stroke-opacity=\"0.75\"/>")
        }

        // Events
        for event in data.events {
            let ex = x(event.time)
            let color = hex(ChartData.eventColor(event.kind))
            let labelWidth = Double(event.kind.label.count) * 7.5 + 14
            out.append("<line x1=\"\(f(ex))\" y1=\"\(f(top))\" x2=\"\(f(ex))\" y2=\"\(f(top + plotH))\" stroke=\"\(color)\" stroke-width=\"1.5\" stroke-opacity=\"0.8\"/>")
            out.append("<rect x=\"\(f(ex))\" y=\"\(f(top - 24))\" width=\"\(f(labelWidth))\" height=\"20\" rx=\"4\" fill=\"\(color)\"/>")
            out.append("<text x=\"\(f(ex + 7))\" y=\"\(f(top - 9))\" \(font) font-size=\"12\" font-weight=\"600\" fill=\"#FFFFFF\">\(esc(event.kind.label))</text>")
        }

        out.append("</svg>")
        return out.joined(separator: "\n")
    }
}
