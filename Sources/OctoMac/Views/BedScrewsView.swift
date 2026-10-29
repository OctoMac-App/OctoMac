import OctoPrintKit
import SwiftUI

/// The bed level as screw turns: one card per corner, saying which way and how far to turn its screw.
struct BedScrewsView: View {
    let session: PrinterSession
    let mesh: BedLevelVisualizer.Mesh

    private var settings: BedScrews.Settings { session.journal.screws ?? BedScrews.Settings() }

    var body: some View {
        // The options sit underneath, so the corner cards get the panel's full width, even in longer languages.
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if let advice = BedScrews.advice(for: mesh, settings: settings) {
                    bed(advice)
                } else {
                    Text("This bed mesh doesn't reach the corners, so there's nothing to go on for the screws.")
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

    private func bed(_ advice: (fixed: BedCorner, corners: [BedCorner: BedScrews.Advice])) -> some View {
        VStack(spacing: 4) {
            Text("Back").font(Typeface.caption).foregroundStyle(Palette.faint)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    card(.backLeft, advice)
                    card(.backRight, advice)
                }
                GridRow {
                    card(.frontLeft, advice)
                    card(.frontRight, advice)
                }
            }
            Text("Front").font(Typeface.caption).foregroundStyle(Palette.faint)
        }
    }

    @ViewBuilder
    private func card(_ corner: BedCorner, _ advice: (fixed: BedCorner, corners: [BedCorner: BedScrews.Advice])) -> some View {
        let item = advice.corners[corner]
        let fixed = corner == advice.fixed
        let level = item?.isLevel ?? true
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: corner.title).font(Typeface.caption).foregroundStyle(Palette.faint)
            if let item, !fixed, !level {
                HStack(spacing: 8) {
                    Image(systemName: item.clockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Palette.warm)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(turns(item.turns)).font(Typeface.number(20)).foregroundStyle(Palette.paper)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(item.clockwise ? "Clockwise" : "Anticlockwise").font(Typeface.bodyStrong).foregroundStyle(Palette.dust)
                            .lineLimit(2).minimumScaleFactor(0.8)
                    }
                }
                Text(item.change > 0 ? "Raises it \(BedMeshColors.format(abs(item.change), signed: false)) mm"
                                     : "Lowers it \(BedMeshColors.format(abs(item.change), signed: false)) mm")
                    .font(Typeface.caption).foregroundStyle(Palette.faint)
            } else if item == nil {
                Text("Not measured").font(Typeface.bodyStrong).foregroundStyle(Palette.faint)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: fixed ? "pin.fill" : "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(fixed ? Palette.dust : Palette.ready)
                    Text("Leave it").font(Typeface.number(20)).foregroundStyle(Palette.paper)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(fixed ? "The others are matched to this corner" : "Level with the others")
                    .font(Typeface.caption).foregroundStyle(Palette.faint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.graphite))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(!fixed && !level ? Palette.warm.opacity(0.5) : Palette.edge, lineWidth: 1))
    }

    private func turns(_ turns: Double) -> String {
        let text = BedScrews.turnsText(turns)
        if text == "0" { return String(localized: "A touch") }
        return turns <= 1.0625 ? String(localized: "\(text) turn") : String(localized: "\(text) turns")
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Side by side when there's room, otherwise one above another, so nothing gets cut short.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { optionMenus(minWidth: 200) }
                VStack(alignment: .leading, spacing: 10) { optionMenus(minWidth: nil) }
            }
            Text("Turn the screws, then measure again to check.")
                .font(Typeface.caption).foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func optionMenus(minWidth: CGFloat?) -> some View {
        option("Screw thread", minWidth: minWidth) {
            PlateMenu(selection: Binding(get: { settings.pitch }, set: { value in update { $0.pitch = value } }),
                      options: BedScrews.pitches.map { ($0.pitch, String(localized: "\($0.name), \(Fmt.number($0.pitch)) mm a turn")) })
        }
        option("Clockwise, from above", minWidth: minWidth) {
            PlateMenu(selection: Binding(get: { settings.clockwiseLowers }, set: { value in update { $0.clockwiseLowers = value } }),
                      options: [(true, String(localized: "Lowers the corner")), (false, String(localized: "Raises the corner"))])
        }
        option("Corner to leave alone", minWidth: minWidth) {
            PlateMenu(selection: Binding(get: { settings.fixed }, set: { value in update { $0.fixed = value } }),
                      options: [(nil, String(localized: "Whichever is easiest"))] + BedCorner.allCases.map { ($0, $0.title) })
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
        session.setScrewSettings(copy)
    }
}
