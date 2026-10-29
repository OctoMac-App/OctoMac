import SwiftUI

/// A choice between a few options, in the same capsule as the tab bar: the chosen one slides along in green.
struct CapsulePicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringKey)]
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

/// A dropdown in the style of the app's text fields: a dark field showing the choice, opening the same dark list as
/// the temperature presets.
struct PlateMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @State private var open = false
    @State private var hovering = false
    @State private var hovered: Int?

    private var title: String { options.first { $0.value == selection }?.title ?? "" }

    var body: some View {
        Button { open.toggle() } label: {
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
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(open ? Palette.accent : Palette.edge, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $open, arrowEdge: .bottom) { list }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    Button {
                        selection = option.value
                        open = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.accent)
                                .opacity(option.value == selection ? 1 : 0)
                            Text(option.title).font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(hovered == index ? Palette.extrusionHi : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
                }
            }
            .padding(6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 260)
        .frame(maxHeight: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.extrusion)
        .presentationBackground(Palette.extrusion)
    }
}

/// One line in an `AppMenu`.
enum AppMenuItem {
    case action(String, symbol: String? = nil, checked: Bool = false, destructive: Bool = false, disabled: Bool = false, run: () -> Void)
    case heading(String)
    case divider
}

/// A dropdown menu in the app's style: any label, opening the same dark list as the temperature presets, rather than
/// a standard macOS menu. Right-click menus stay standard.
struct AppMenu<Label: View>: View {
    let items: [AppMenuItem]
    var width: CGFloat = 240
    @ViewBuilder let label: () -> Label
    @State private var open = false
    @State private var hovered: Int?

    var body: some View {
        Button { open.toggle() } label: { label() }
            .buttonStyle(.plain)
            .fixedSize()
            .popover(isPresented: $open, arrowEdge: .bottom) { list }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                switch items[index] {
                case .heading(let title):
                    Text(title).font(Typeface.caption).foregroundStyle(Palette.faint)
                        .padding(.horizontal, 10).padding(.top, index == 0 ? 2 : 6).padding(.bottom, 2)
                case .divider:
                    Divider().overlay(Palette.edge).padding(.vertical, 4).padding(.horizontal, 6)
                case .action(let title, let symbol, let checked, let destructive, let disabled, let run):
                    Button {
                        open = false
                        // Let the menu close before anything that opens a window or a save panel.
                        DispatchQueue.main.async(execute: run)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: checked ? "checkmark" : (symbol ?? "circle"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(checked ? Palette.accent : (destructive ? Palette.hot : Palette.dust))
                                .frame(width: 14)
                                .opacity(checked || symbol != nil ? 1 : 0)
                            Text(title).font(Typeface.bodyStrong)
                                .foregroundStyle(destructive ? Palette.hot : Palette.paper)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(hovered == index && !disabled ? Palette.extrusionHi : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                    .opacity(disabled ? 0.4 : 1)
                    .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
                }
            }
        }
        .padding(6)
        .frame(width: width)
        .background(Palette.extrusion)
        .presentationBackground(Palette.extrusion)
    }
}
