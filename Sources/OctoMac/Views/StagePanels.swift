import OctoPrintKit
import SwiftUI
import UniformTypeIdentifiers

/// A titled panel on the stage.
struct StagePanel<Content: View>: View {
    let title: String
    var detail: String?
    var fills = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelHeading(title: title, detail: detail)
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .topLeading)
        .machined(radius: 20)
    }
}

/// Explains why controls are disabled.
struct StageNotice: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(Typeface.bodyStrong)
            .foregroundStyle(Palette.warm)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Palette.warm.opacity(0.12)))
    }
}
