import SwiftUI

/// A choice between a few options, in the same capsule as the tab bar: the chosen one slides along in green.
struct CapsulePicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var compact = false
    @Namespace private var carriage

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(Typeface.text(compact ? 12 : 13, .demibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selected ? Palette.graphite : Palette.dust)
                        .padding(.horizontal, compact ? 11 : 14)
                        .padding(.vertical, compact ? 4 : 6)
                        .background {
                            if selected { Capsule().fill(Palette.accent).matchedGeometryEffect(id: "carriage", in: carriage) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Palette.graphite))
        .overlay(Capsule().strokeBorder(Palette.edge, lineWidth: 1))
        .fixedSize()
    }
}

/// A dropdown in the style of the app's text fields: a dark field showing the choice, opening a menu of options.
struct PlateMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @State private var hovering = false

    private var title: String { options.first { $0.value == selection }?.title ?? "" }

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Toggle(option.title, isOn: Binding(get: { option.value == selection }, set: { if $0 { selection = option.value } }))
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(Typeface.body)
                    .foregroundStyle(Palette.paper)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Palette.extrusionHi : Palette.graphite))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.edge, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
    }
}
