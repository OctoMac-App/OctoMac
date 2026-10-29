import OctoPrintKit
import SwiftUI

/// The bed level as screw turns: one card per screw, saying which way and how far to turn it. Printers that allow for
/// the bed's shape by themselves (a stock Prusa) get an explanation instead.
struct BedScrewsView: View {
    let session: PrinterSession
    let mesh: BedLevelVisualizer.Mesh

    private var settings: BedScrews.Settings { session.journal.screws ?? BedScrews.Settings() }

    /// OctoMac's guess, used until you choose a layout yourself.
    private var guess: (layout: BedScrews.Layout, clue: String?) {
        BedScrews.guess(firmware: session.firmware, model: session.currentProfile?.model,
                        prusaAdjustments: session.bedLevel?.prusaAdjustments ?? false)
    }

    private var layout: BedScrews.Layout { settings.layout ?? guess.layout }

    var body: some View {
        // The options sit underneath, so the cards get the panel's full width, even in longer languages.
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if layout == .none {
                    nothingToTurn
                } else if let advice = BedScrews.advice(for: mesh, layout: layout, settings: settings) {
                    bed(advice)
                } else {
                    Text("This bed mesh doesn't reach far enough across the bed, so there's nothing to go on for the screws.")
                        .font(Typeface.body).foregroundStyle(Palette.dust)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .overlay {
                if session.bedMeasuringSince != nil {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.graphite.opacity(0.7))
                    ProgressView().controlSize(.large).tint(Palette.accent)
                }
            }
            options
        }
    }

    // MARK: Nothing to turn

    private var nothingToTurn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Nothing to turn", systemImage: "checkmark.seal.fill")
                .font(Typeface.subhead).foregroundStyle(Palette.paper)
                .labelStyle(TitleAndIconLabelStyle())
            Text("This printer measures the bed before every print and allows for its shape, so it has no levelling screws to turn.")
                .font(Typeface.body).foregroundStyle(Palette.dust)
                .fixedSize(horizontal: false, vertical: true)
            if let spread = mesh.spread {
                Text("Highest to lowest point: \(BedMeshColors.format(spread, signed: false)) mm. Under 0.2 mm is good, and more can still print fine.")
                    .font(Typeface.body).foregroundStyle(Palette.dust)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("If the first layer still looks thin or squashed on one side, adjust Bed level correction in the printer's Calibration menu. The first layer shows which way. If your bed has adjustable screws (the nylock mod), choose Nine screws below.")
                .font(Typeface.caption).foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.graphite))
    }

    // MARK: Screws

    private func bed(_ advice: (fixed: BedPoint, points: [BedPoint: BedScrews.Advice])) -> some View {
        let compact = layout == .nine
        let rows: [[BedPoint]] = compact
            ? [[.backLeft, .back, .backRight], [.left, .centre, .right], [.frontLeft, .front, .frontRight]]
            : [[.backLeft, .backRight], [.frontLeft, .frontRight]]
        return VStack(spacing: 4) {
            Text("Back").font(Typeface.caption).foregroundStyle(Palette.faint)
            Grid(horizontalSpacing: compact ? 8 : 10, verticalSpacing: compact ? 8 : 10) {
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(rows[row]) { point in card(point, advice, compact: compact) }
                    }
                }
            }
            Text("Front").font(Typeface.caption).foregroundStyle(Palette.faint)
        }
    }

    @ViewBuilder
    private func card(_ point: BedPoint, _ advice: (fixed: BedPoint, points: [BedPoint: BedScrews.Advice]), compact: Bool) -> some View {
        let item = advice.points[point]
        let fixed = point == advice.fixed
        let level = item?.isLevel ?? true
        let size: CGFloat = compact ? 16 : 20
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            Text(verbatim: point.title).font(Typeface.caption).foregroundStyle(Palette.faint).lineLimit(1)
            if let item, !fixed, !level {
                HStack(spacing: 8) {
                    Image(systemName: item.clockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                        .font(.system(size: size, weight: .bold))
                        .foregroundStyle(Palette.warm)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(compact ? "\(BedScrews.degrees(item.turns))°" : turns(item.turns))
                            .font(Typeface.number(size)).foregroundStyle(Palette.paper)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(item.clockwise ? "Clockwise" : "Anticlockwise").font(compact ? Typeface.caption : Typeface.bodyStrong)
                            .foregroundStyle(Palette.dust)
                            .lineLimit(2).minimumScaleFactor(0.8)
                    }
                }
                if !compact {
                    Text(change(item)).font(Typeface.caption).foregroundStyle(Palette.faint)
                }
            } else if item == nil {
                Text("Not measured").font(Typeface.bodyStrong).foregroundStyle(Palette.faint)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: fixed ? "pin.fill" : "checkmark.circle.fill")
                        .font(.system(size: size - 2, weight: .semibold))
                        .foregroundStyle(fixed ? Palette.dust : Palette.ready)
                    Text("Leave it").font(Typeface.number(size)).foregroundStyle(Palette.paper)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                if !compact {
                    Text(fixed ? "The others are matched to this one" : "Level with the others")
                        .font(Typeface.caption).foregroundStyle(Palette.faint)
                }
            }
        }
        .padding(compact ? 9 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.graphite))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(!fixed && !level ? Palette.warm.opacity(0.5) : Palette.edge, lineWidth: 1))
        .help(item.map { fixed ? String(localized: "The others are matched to this one") : change($0) } ?? "")
    }

    private func change(_ item: BedScrews.Advice) -> String {
        let amount = BedMeshColors.format(abs(item.change), signed: false)
        return item.change > 0 ? String(localized: "Raises it \(amount) mm") : String(localized: "Lowers it \(amount) mm")
    }

    private func turns(_ turns: Double) -> String {
        let text = BedScrews.turnsText(turns)
        if text == "0" { return String(localized: "A touch") }
        return turns <= 1.0625 ? String(localized: "\(text) turn") : String(localized: "\(text) turns")
    }

    // MARK: Options

    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Side by side when there's room, otherwise one above another, so nothing gets cut short.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { optionMenus(minWidth: 200) }
                LazyVGrid(columns: [GridItem(.flexible(minimum: 200), spacing: 12, alignment: .top),
                                    GridItem(.flexible(minimum: 200), spacing: 12, alignment: .top)],
                          alignment: .leading, spacing: 10) { optionMenus(minWidth: 200) }
                VStack(alignment: .leading, spacing: 10) { optionMenus(minWidth: nil) }
            }
            Group {
                if settings.layout == nil, let clue = guess.clue {
                    Text("Bed chosen from what OctoMac could see (\(clue)). Change it if that's not right.")
                } else if layout != .none {
                    Text("Turn the screws, then measure again to check.")
                }
            }
            .font(Typeface.caption).foregroundStyle(Palette.faint)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func optionMenus(minWidth: CGFloat?) -> some View {
        option("Bed", minWidth: minWidth) {
            PlateMenu(selection: Binding(get: { layout }, set: { value in update { $0.layout = value } }),
                      options: [(.corners, String(localized: "Four corner screws")),
                                (.nine, String(localized: "Nine screws (nylock mod)")),
                                (.none, String(localized: "No screws to turn"))])
        }
        if layout != .none {
            option("Screw thread", minWidth: minWidth) {
                PlateMenu(selection: Binding(get: { settings.pitch }, set: { value in update { $0.pitch = value } }),
                          options: BedScrews.pitches.map { ($0.pitch, String(localized: "\($0.name), \(Fmt.number($0.pitch)) mm a turn")) })
            }
            option("Clockwise, from above", minWidth: minWidth) {
                PlateMenu(selection: Binding(get: { settings.clockwiseLowers }, set: { value in update { $0.clockwiseLowers = value } }),
                          options: [(true, String(localized: "Lowers the bed")), (false, String(localized: "Raises the bed"))])
            }
            option("Screw to leave alone", minWidth: minWidth) {
                PlateMenu(selection: Binding(get: { settings.fixed }, set: { value in update { $0.fixed = value } }),
                          options: [(nil, layout == .nine ? String(localized: "Centre (usual)") : String(localized: "Whichever is easiest"))]
                              + layout.points.filter { layout != .nine || $0 != .centre }.map { ($0, $0.title) })
            }
        }
    }

    private func option<Content: View>(_ title: LocalizedStringKey, minWidth: CGFloat?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(Typeface.caption).foregroundStyle(Palette.faint).lineLimit(1)
            content()
        }
        .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .leading)
    }

    private func update(_ change: (inout BedScrews.Settings) -> Void) {
        var copy = settings
        change(&copy)
        // Changing the layout starts the fixed screw afresh, since the old one may not be part of the new layout.
        if copy.layout != settings.layout { copy.fixed = nil }
        session.setScrewSettings(copy)
    }
}
