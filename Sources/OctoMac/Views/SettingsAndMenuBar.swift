import OctoPrintKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(InstanceStore.self) private var store
    @State private var selection: UUID?
    @State private var editor: EditorTarget?

    var body: some View {
        TabView {
            VStack(alignment: .leading) {
                List(selection: $selection) {
                    ForEach(store.instances) { instance in
                        VStack(alignment: .leading) {
                            Text(instance.name)
                            Text(instance.baseURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(instance.id)
                    }
                    .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                }
                .contextMenu(forSelectionType: UUID.self) { _ in } primaryAction: { ids in
                    if let id = ids.first, let instance = store.instances.first(where: { $0.id == id }) { editor = .edit(instance) }
                }
                HStack(spacing: 0) {
                    Button { editor = .new } label: { Image(systemName: "plus").frame(width: 20, height: 16) }
                    Button {
                        if let selection { store.remove(selection) }
                        selection = nil
                    } label: { Image(systemName: "minus").frame(width: 20, height: 16) }
                        .disabled(selection == nil)
                    Spacer()
                    Button("Edit…") {
                        if let instance = store.instances.first(where: { $0.id == selection }) { editor = .edit(instance) }
                    }
                    .disabled(selection == nil)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .tabItem { Label("Printers", systemImage: "printer") }

            NotificationSettings()
                .padding()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
        }
        .frame(width: 520, height: 440)
        .sheet(item: $editor) { InstanceEditor(target: $0) }
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
        Form {
            Section {
                ForEach(NotificationKind.allCases) { kind in
                    NotificationToggle(kind: kind)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    switch status {
                    case .denied:
                        Text("Notifications are turned off for OctoMac in System Settings.")
                        Button("Open Notification Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    case .notDetermined:
                        Button("Allow Notifications") { Task { _ = await Notifier.shared.requestPermission(); await refresh() } }
                    default:
                        Text("Banners for the printer on screen are skipped while OctoMac is in front.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
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
            Text(kind.title)
            Text(kind.detail)
        }
    }
}
