import OctoPrintKit
import SwiftUI
import UserNotifications

/// OctoMac's Settings window, in the same style as the main window.
struct SettingsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case printers = "Printers", notifications = "Notifications"
        var id: String { rawValue }
    }

    @State private var page = Page.printers
    @Namespace private var carriage

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 2) {
                ForEach(Page.allCases) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { page = item }
                    } label: {
                        Text(item.rawValue)
                            .font(Typeface.text(13, .demibold))
                            .foregroundStyle(page == item ? Palette.graphite : Palette.dust)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background {
                                if page == item { Capsule().fill(Palette.accent).matchedGeometryEffect(id: "carriage", in: carriage) }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Capsule().fill(Palette.extrusion))
            .overlay(Capsule().strokeBorder(.white.opacity(0.05), lineWidth: 1))

            switch page {
            case .printers: PrinterSettings()
            case .notifications: NotificationSettings()
            }
        }
        .padding(24)
        .frame(width: 560, height: 520, alignment: .top)
        .background(Palette.graphite)
        .containerBackground(Palette.graphite, for: .window)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

private struct PrinterSettings: View {
    @Environment(InstanceStore.self) private var store
    @State private var editor: EditorTarget?
    @State private var removing: Instance?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.isDemo {
                Text("Demo mode is on. Your own printers come back when you leave it.")
                    .font(Typeface.caption).foregroundStyle(Palette.warm)
            }
            List {
                ForEach(store.instances) { instance in
                    PrinterSettingsRow(instance: instance, tint: store.filament(for: instance)) {
                        editor = .edit(instance)
                    } remove: {
                        removing = instance
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if store.instances.isEmpty {
                    Text("No printers yet.").font(Typeface.body).foregroundStyle(Palette.faint)
                }
            }

            HStack {
                Text("Drag to reorder. Double-click a printer to edit it.")
                    .font(Typeface.caption).foregroundStyle(Palette.faint)
                Spacer()
                Button { editor = .new } label: { Label("Add a printer", systemImage: "plus") }
                    .buttonStyle(.plate)
            }
        }
        .sheet(item: $editor) { InstanceEditor(target: $0) }
        .sheet(item: $removing) { instance in
            ConfirmSheet(symbol: "trash", title: "Remove \(instance.name)?",
                         message: "OctoMac forgets this printer and its API key. Nothing changes on the printer or in OctoPrint.",
                         confirmTitle: "Remove", onConfirm: { store.remove(instance.id) })
        }
    }
}

private struct PrinterSettingsRow: View {
    let instance: Instance
    let tint: Color
    let edit: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name).font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(1)
                Text(instance.baseURL.absoluteString).font(Typeface.caption).foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer()
            Button("Edit", action: edit).buttonStyle(.plateQuiet).controlSize(.small)
            Button(action: remove) { Image(systemName: "trash") }
                .buttonStyle(.plateQuiet).controlSize(.small)
                .help("Remove this printer from OctoMac")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .machined(radius: 12, fill: hovering ? Palette.extrusionHi : Palette.extrusion)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: edit)
    }
}

struct MenuBarView: View {
    @Environment(InstanceStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage("selectedInstance") private var selectedInstance = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                BrandLockup(markSize: 24)
                Spacer()
                Text(summary).font(Typeface.caption).foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 4)

            ForEach(store.instances) { instance in
                if let session = store.sessions[instance.id] {
                    Button { open(instance) } label: {
                        MenuPrinterCard(session: session, filament: store.filament(for: instance))
                    }
                    .buttonStyle(.plain)
                }
            }

            if store.instances.isEmpty {
                Text("No printers yet. Open OctoMac to add one.")
                    .font(Typeface.body).foregroundStyle(Palette.dust)
                    .padding(.vertical, 12)
            }

            HStack {
                Button("Open OctoMac") { open(nil) }.buttonStyle(.plateQuiet)
                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.faint)
                    .help("Quit OctoMac")
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 360)
        .background(Palette.graphite)
    }

    private var summary: String {
        let printing = store.instances.compactMap { store.sessions[$0.id] }.filter(\.flags.isJobActive).count
        return printing == 0 ? "Nothing printing" : printing == 1 ? "1 printing" : "\(printing) printing"
    }

    private func open(_ instance: Instance?) {
        if let instance { selectedInstance = instance.id.uuidString }
        openWindow(id: "main")
        NSApp.activate()
    }
}

struct MenuPrinterCard: View {
    let session: PrinterSession
    let filament: Color
    @State private var hovering = false

    var body: some View {
        let mood = PrinterMood(session)
        let running = session.flags.isJobActive
        HStack(alignment: .top, spacing: 12) {
            Capsule().fill(filament).frame(width: 4)

            if running {
                FileThumbnail(file: session.fileEntry(for: session.job?.file), client: session.client, tint: filament, radius: 8)
                    .frame(width: 48, height: 48)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(session.instance.name).font(Typeface.text(14, .demibold)).foregroundStyle(Palette.paper)
                    Spacer()
                    StatusLamp(color: mood.color(filament: filament), lit: mood != .offline)
                }

                if running {
                    Text(SlicedName(session.job?.file.displayName ?? "").title)
                        .font(Typeface.caption).foregroundStyle(Palette.dust).lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.edge.opacity(0.5))
                            Capsule().fill(filament).frame(width: geo.size.width * (session.progress?.fraction ?? 0))
                        }
                    }
                    .frame(height: 4)
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int((session.progress?.fraction ?? 0) * 100))%").font(Typeface.number(18)).foregroundStyle(Palette.paper)
                        Spacer()
                        Text("\(Fmt.duration(session.progress?.printTimeLeft)) left, done \(Fmt.eta(session.progress?.printTimeLeft))")
                            .font(Typeface.number(12)).foregroundStyle(Palette.dust)
                    }
                } else {
                    HStack(spacing: 12) {
                        Text(session.stateText).font(Typeface.caption).foregroundStyle(Palette.dust).lineLimit(1)
                        Spacer()
                        ForEach(session.heaters.filter { HeaterKind(key: $0.key).isHeater && $0.value.actual != nil }.keys.sorted(), id: \.self) { key in
                            let value = session.heaters[key]?.actual
                            HStack(spacing: 3) {
                                Image(systemName: HeaterKind(key: key).symbol)
                                    .font(.system(size: 9)).foregroundStyle(HeaterKind(key: key).color)
                                Text(value.map { "\(Int($0))°" } ?? "–").font(Typeface.number(12)).foregroundStyle(Palette.dust)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .machined(radius: 12, fill: hovering ? Palette.extrusionHi : Palette.extrusion)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Menu bar icon: a printer glyph, plus the progress of the print finishing soonest while anything is printing.
struct MenuBarLabel: View {
    @Environment(InstanceStore.self) private var store

    var body: some View {
        let active = store.instances.compactMap { store.sessions[$0.id] }.filter(\.flags.isJobActive)
        let soonest = active.min { ($0.progress?.printTimeLeft ?? .infinity) < ($1.progress?.printTimeLeft ?? .infinity) }
        HStack(spacing: 4) {
            Image(systemName: "printer.fill")
            if let soonest, let fraction = soonest.progress?.fraction {
                Text("\(Int(fraction * 100))%").monospacedDigit()
            }
        }
    }
}

struct NotificationSettings: View {
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if status == .denied || status == .notDetermined {
                HStack(spacing: 12) {
                    Image(systemName: "bell.slash.fill").foregroundStyle(Palette.warm)
                    Text(status == .denied ? "Notifications are turned off for OctoMac in System Settings." : "OctoMac hasn't been allowed to send notifications yet.")
                        .font(Typeface.body).foregroundStyle(Palette.paper)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(status == .denied ? "Open System Settings" : "Allow") {
                        if status == .denied {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        } else {
                            Task { _ = await Notifier.shared.requestPermission(); await refresh() }
                        }
                    }
                    .buttonStyle(.plate)
                    .controlSize(.small)
                }
                .padding(14)
                .machined(radius: 12, fill: Palette.warm.opacity(0.1))
            }

            VStack(spacing: 0) {
                ForEach(NotificationKind.allCases) { kind in
                    NotificationToggle(kind: kind)
                    if kind != NotificationKind.allCases.last { Divider().overlay(Palette.edge) }
                }
            }
            .machined(radius: 14)

            Text("Banners for the printer on screen are skipped while OctoMac is in front.")
                .font(Typeface.caption).foregroundStyle(Palette.faint)
        }
        .task { await refresh() }
        // Coming back from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async { status = await Notifier.shared.permissionStatus() }
}

private struct NotificationToggle: View {
    let kind: NotificationKind
    @AppStorage private var enabled: Bool

    init(kind: NotificationKind) {
        self.kind = kind
        _enabled = AppStorage(wrappedValue: true, kind.defaultsKey)
    }

    var body: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                Text(kind.detail).font(Typeface.caption).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(Palette.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
