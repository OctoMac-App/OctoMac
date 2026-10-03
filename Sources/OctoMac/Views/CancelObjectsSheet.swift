import OctoPrintKit
import SwiftUI

/// Cancel Objects: the parts on the plate, drawn where they sit on the bed, each of which can be stopped on its own
/// while the rest carry on printing.
struct CancelObjectsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    let filament: Color
    @State private var selected: Int?
    @State private var confirming: CancelObject.Object?

    private var objects: [CancelObject.Object] { session.printObjects.filter { !$0.ignored } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Objects on the plate").font(Typeface.title).foregroundStyle(Palette.paper)
                Text("Stop one part if it's failed, and the others carry on printing. A cancelled part can't be resumed.")
                    .font(Typeface.body).foregroundStyle(Palette.dust)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 20) {
                PlateMap(objects: objects, volume: session.currentProfile?.volume, active: session.activeObjectID,
                         selected: $selected, filament: filament)
                    .frame(width: 300, height: 260)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(objects) { object in
                            row(object)
                        }
                    }
                }
                .frame(height: 260)
            }
            HStack {
                Text("Objects come from the labels your slicer adds to the G-code.")
                    .font(Typeface.caption).foregroundStyle(Palette.faint)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.plate).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 720)
        .background(Palette.extrusion)
        .sheet(item: $confirming) { object in
            ConfirmSheet(symbol: "xmark.octagon", title: "Stop printing \(object.displayName)?",
                         message: "OctoPrint skips this part for the rest of the print. The other parts carry on, and this can't be undone.",
                         confirmTitle: "Stop this part", onConfirm: { session.cancel(object) })
        }
    }

    private func row(_ object: CancelObject.Object) -> some View {
        let active = session.activeObjectID == object.id && !object.cancelled
        return HStack(spacing: 10) {
            Circle()
                .fill(object.cancelled ? Palette.hot : active ? filament : Palette.edge)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(object.displayName)
                    .font(Typeface.bodyStrong)
                    .foregroundStyle(object.cancelled ? Palette.faint : Palette.paper)
                    .strikethrough(object.cancelled)
                    .lineLimit(1)
                Text(object.cancelled ? "Cancelled" : active ? "Printing now" : "Printing")
                    .font(Typeface.caption).foregroundStyle(object.cancelled ? Palette.hot : Palette.faint)
            }
            Spacer()
            if !object.cancelled {
                Button("Stop") { confirming = object }
                    .buttonStyle(.plateQuiet)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected == object.id ? Palette.extrusionHi : Palette.graphite))
        .contentShape(Rectangle())
        .onHover { selected = $0 ? object.id : (selected == object.id ? nil : selected) }
    }
}

/// The bed seen from above (front at the bottom) with each object's footprint.
private struct PlateMap: View {
    let objects: [CancelObject.Object]
    let volume: PrinterProfile.Volume?
    let active: Int?
    @Binding var selected: Int?
    let filament: Color

    var body: some View {
        let width = volume?.width ?? 250, depth = volume?.depth ?? 210
        GeometryReader { geo in
            let scale = min(geo.size.width / width, geo.size.height / depth)
            let bed = CGSize(width: width * scale, height: depth * scale)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.graphite)
                    .frame(width: bed.width, height: bed.height)
                ForEach(objects) { object in
                    if let b = object.bounds {
                        let rect = CGRect(x: b.minX * scale, y: (depth - b.maxY) * scale,
                                          width: max(4, (b.maxX - b.minX) * scale), height: max(4, (b.maxY - b.minY) * scale))
                        let isActive = active == object.id && !object.cancelled
                        RoundedRectangle(cornerRadius: 3)
                            .fill(object.cancelled ? Palette.hot.opacity(0.25) : filament.opacity(isActive ? 0.85 : 0.45))
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(selected == object.id ? Palette.paper : .clear, lineWidth: 2))
                            .overlay {
                                if object.cancelled { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.hot) }
                            }
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .onHover { selected = $0 ? object.id : nil }
                    }
                }
            }
            .frame(width: bed.width, height: bed.height)
            .overlay(alignment: .bottom) {
                Text("Front").font(Typeface.caption).foregroundStyle(Palette.faint).offset(y: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
