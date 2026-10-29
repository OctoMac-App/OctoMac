import Charts
import OctoPrintKit
import SwiftUI

/// The top of the History tab: lifetime totals and the last twelve months, for this printer or all of them.
struct StatisticsPanel: View {
    @Environment(InstanceStore.self) private var store
    let session: PrinterSession
    let filament: Color
    @AppStorage("statistics.allPrinters") private var allPrinters = false
    @State private var hoverMonth: Date?

    private var stats: PrintStatistics {
        let sessions = allPrinters ? store.instances.compactMap { store.sessions[$0.id] } : [session]
        let parts = sessions.map { PrintStatistics(files: $0.files, log: $0.printLog) }
        return parts.count == 1 ? parts[0] : PrintStatistics(combining: parts)
    }

    var body: some View {
        let stats = stats
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                PanelHeading(title: "Statistics", detail: nil)
                Spacer()
                if store.instances.count > 1 {
                    CapsulePicker(selection: $allPrinters, options: [(false, "This printer"), (true, "All printers")], compact: true)
                }
            }
            HStack(alignment: .top, spacing: 24) {
                tiles(stats)
                    .frame(width: 300, alignment: .leading)
                MonthsChart(months: stats.months, color: allPrinters ? Palette.accent : filament, hoverMonth: $hoverMonth)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 150)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .machined(radius: 20)
    }

    private func tiles(_ stats: PrintStatistics) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 16) {
            GridRow {
                tile("Prints", value: "\(stats.total)",
                     note: stats.total == 0 ? "None yet" : "\(stats.finished) finished")
                tile("Finished", value: stats.successRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "–",
                     note: stats.failed == 0 ? "No failures" : "\(stats.failed) failed or stopped")
            }
            GridRow {
                tile("Printing time", value: stats.printingTime > 0 ? Fmt.duration(stats.printingTime) : "–",
                     note: "Finished prints, about")
                tile("Filament", value: stats.filament > 0 ? Self.metres(stats.filament) : "–",
                     note: stats.favourites.first.map { "Most printed: \($0.name)" } ?? "Finished prints")
            }
        }
        .help("From OctoPrint's records of each file: how often it finished or failed, and its usual print time and filament.")
    }

    private func tile(_ title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Typeface.caption).foregroundStyle(Palette.faint)
            Text(value).font(Typeface.number(22)).foregroundStyle(Palette.paper).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(Typeface.caption).foregroundStyle(Palette.dust).lineLimit(1).truncationMode(.tail)
        }
    }

    static func metres(_ mm: Double) -> String {
        let metres = mm / 1000
        return metres >= 1000 ? String(format: "%.1f km", metres / 1000) : "\(Int(metres.rounded())) m"
    }
}

/// Prints per month as bars, finished below and failed stacked on top, with a hover readout for each month.
private struct MonthsChart: View {
    let months: [PrintStatistics.Month]
    let color: Color
    @Binding var hoverMonth: Date?

    private var hovered: PrintStatistics.Month? { months.first { $0.start == hoverMonth } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Text("Prints per month").font(Typeface.caption).foregroundStyle(Palette.faint)
                Spacer()
                legend("Finished", color)
                legend("Failed or stopped", Palette.hot)
            }
            Chart {
                ForEach(months) { month in
                    BarMark(x: .value("Month", month.start, unit: .month), y: .value("Prints", month.finished))
                        .foregroundStyle(color.opacity(hoverMonth == nil || hoverMonth == month.start ? 1 : 0.45))
                        .cornerRadius(month.failed == 0 ? 4 : 0)
                    if month.failed > 0 {
                        BarMark(x: .value("Month", month.start, unit: .month), y: .value("Prints", month.failed))
                            .foregroundStyle(Palette.hot.opacity(hoverMonth == nil || hoverMonth == month.start ? 1 : 0.45))
                            .cornerRadius(4)
                    }
                }
                if let hovered {
                    RuleMark(x: .value("Month", hovered.start, unit: .month))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, alignment: .center, spacing: 0,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            MonthTooltip(month: hovered)
                        }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plot = proxy.plotFrame,
                                      let date = proxy.value(atX: location.x - geo[plot].origin.x, as: Date.self) else { return }
                                hoverMonth = Calendar.current.dateInterval(of: .month, for: date)?.start
                            case .ended:
                                hoverMonth = nil
                            }
                        }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Palette.edge.opacity(0.6))
                    AxisValueLabel {
                        if let count = value.as(Int.self) { Text("\(count)").font(Typeface.number(11)).foregroundStyle(Palette.faint) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.month(.narrow)).font(Typeface.number(11)).foregroundStyle(Palette.faint)
                        }
                    }
                }
            }
        }
        .help("Months before OctoMac was watching only count each file's latest print.")
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(title).font(Typeface.caption).foregroundStyle(Palette.dust)
        }
    }
}

private struct MonthTooltip: View {
    let month: PrintStatistics.Month

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(month.start, format: .dateTime.month(.wide).year())
                .font(Typeface.number(12)).foregroundStyle(Palette.faint)
            Text(month.total == 1 ? "1 print" : "\(month.total) prints")
                .font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
            if month.total > 0 {
                Text("\(month.finished) finished, \(month.failed) failed or stopped")
                    .font(Typeface.caption).foregroundStyle(Palette.dust)
                if month.hours > 0 {
                    Text("\(Fmt.duration(month.hours * 3600)) printing")
                        .font(Typeface.caption).foregroundStyle(Palette.dust)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.extrusionHi))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.edge, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}
