import OctoPrintKit
import SwiftUI

// MARK: - Firmware warnings

/// OctoPrint's Firmware Check: the printer's firmware is unsafe, known to be broken, or a development build.
struct FirmwareWarningsPanel: View {
    let warnings: [FirmwareCheck.Warning]

    var body: some View {
        StagePanel(title: "Firmware warning") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(warnings) { warning in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: warning.isCritical ? "exclamationmark.octagon.fill" : "info.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(warning.isCritical ? Palette.hot : Palette.warm)
                        VStack(alignment: .leading, spacing: 6) {
                            if let summary = summary(warning.type) {
                                Text(summary).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            // OctoPrint's own words, which name the exact problem.
                            Text(verbatim: warning.message).font(Typeface.caption).foregroundStyle(Palette.dust)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            if let url = warning.url {
                                Link(destination: url) { Label("What to do about it", systemImage: "arrow.up.right.square") }
                                    .font(Typeface.caption)
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                    }
                }
            }
        }
    }

    private func summary(_ type: String) -> LocalizedStringKey? {
        switch type {
        case "firmware-unsafe": "This printer's firmware has a known safety problem. Don't leave it printing alone until it's fixed."
        case "firmware-broken": "This printer's firmware has a known bug that can spoil prints or upset OctoPrint."
        case "firmware-development": "This printer is running a test version of its firmware, which may have bugs."
        default: nil
        }
    }
}

// MARK: - Messages from the printer

/// Messages the printer's firmware sends with `//action:notification`, newest first.
struct PrinterMessagesPanel: View {
    let session: PrinterSession

    var body: some View {
        let notes = Array(session.printerNotes.suffix(8).reversed())
        StagePanel(title: "Messages from the printer") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(notes) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(note.date.formatted(date: .omitted, time: .shortened))
                            .font(Typeface.number(12)).foregroundStyle(Palette.faint)
                            .frame(width: 54, alignment: .leading)
                        Text(verbatim: note.message).font(Typeface.body).foregroundStyle(Palette.paper)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                }
                HStack {
                    if session.printerNotes.count > notes.count {
                        Text("And \(session.printerNotes.count - notes.count) earlier").font(Typeface.caption).foregroundStyle(Palette.faint)
                    }
                    Spacer()
                    Button("Clear") { session.clearPrinterNotes() }
                        .buttonStyle(.plateQuiet)
                        .controlSize(.small)
                }
            }
        }
    }
}

// MARK: - OctoPrint's health

/// What OctoPrint's own health checks found, shown in the server panel.
struct ServerHealthList: View {
    let session: PrinterSession
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(session.serverHealth) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.result == .issue ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(item.result == .issue ? Palette.hot : Palette.warm)
                    Text(item.summary).font(Typeface.body).foregroundStyle(Palette.paper)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button {
                    checking = true
                    Task {
                        await session.recheckServerHealth()
                        checking = false
                    }
                } label: {
                    if checking { ProgressView().controlSize(.small) } else { Text("Check again") }
                }
                .buttonStyle(.plateQuiet)
                .controlSize(.small)
                .disabled(checking)
            }
        }
        .padding(14)
        .machined(radius: 12, fill: Palette.graphite)
    }
}

// MARK: - OctoPrint settings

/// Settings that otherwise need OctoPrint's web page: the camera and the temperature presets.
struct OctoPrintSettingsPanel: View {
    let session: PrinterSession
    @State private var editingCamera = false
    @State private var editingPresets = false

    var body: some View {
        let camera = session.cameraSettings
        let presets = session.temperaturePresetDrafts
        StagePanel(title: "OctoPrint settings") {
            VStack(spacing: 8) {
                row(symbol: "web.camera", title: "Camera",
                    detail: camera.fromOtherPlugin ? String(localized: "Set up by another plugin")
                        : camera.stream.isEmpty ? String(localized: "No camera") : camera.stream) { editingCamera = true }
                    .disabled(camera.fromOtherPlugin)
                row(symbol: "thermometer.medium", title: "Temperature presets",
                    detail: presets.isEmpty ? String(localized: "None yet") : presets.map(\.name).formatted(.list(type: .and, width: .narrow))) {
                    editingPresets = true
                }
            }
        }
        .sheet(isPresented: $editingCamera) { CameraSettingsSheet(session: session) }
        .sheet(isPresented: $editingPresets) { TemperaturePresetsSheet(session: session) }
    }

    private func row(symbol: String, title: LocalizedStringKey, detail: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Palette.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                Text(verbatim: detail).font(Typeface.caption).foregroundStyle(Palette.faint).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Change…", action: action)
                .buttonStyle(.plateQuiet)
                .controlSize(.small)
        }
        .padding(12)
        .machined(radius: 12, fill: Palette.graphite)
    }
}

/// The classic webcam's addresses and which way up it is.
struct CameraSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    @State private var camera: CameraSettings

    init(session: PrinterSession) {
        self.session = session
        _camera = State(initialValue: session.cameraSettings)
    }

    var body: some View {
        SettingsSheet(title: "Camera", intro: "Where OctoPrint finds the camera's video and still pictures. Addresses starting with / are on the Raspberry Pi itself.") {
            field("Video stream", text: $camera.stream, prompt: "/webcam/?action=stream")
            field("Still picture", text: $camera.snapshot, prompt: "http://127.0.0.1:8080/?action=snapshot")
            VStack(spacing: 10) {
                toggle("Flip left to right", isOn: $camera.flipH)
                toggle("Flip upside down", isOn: $camera.flipV)
                toggle("Turn a quarter turn anticlockwise", isOn: $camera.rotate90)
            }
            .padding(14)
            .machined(radius: 12, fill: Palette.graphite)
        } save: {
            session.saveCameraSettings(camera)
            dismiss()
        }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Typeface.caption).foregroundStyle(Palette.faint)
            TextField(text: text, prompt: Text(verbatim: prompt)) { EmptyView() }
                .font(.system(size: 13, design: .monospaced))
                .plateField()
        }
    }

    private func toggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(Typeface.body).foregroundStyle(Palette.paper).frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(Palette.accent)
        .controlSize(.small)
    }
}

/// OctoPrint's temperature presets: a name and temperatures for the nozzle and bed.
struct TemperaturePresetsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    @State private var presets: [TemperaturePresetDraft]

    init(session: PrinterSession) {
        self.session = session
        _presets = State(initialValue: session.temperaturePresetDrafts)
    }

    private var valid: Bool {
        presets.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        SettingsSheet(title: "Temperature presets", intro: "One click heats the nozzle and bed for a material. They're shared with OctoPrint's own page.", canSave: valid) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Name")
                    Text("Nozzle")
                    Text("Bed")
                    Color.clear.frame(width: 1, height: 1)
                }
                .font(Typeface.caption).foregroundStyle(Palette.faint)
                ForEach($presets) { $preset in
                    GridRow {
                        TextField("For example, PETG", text: $preset.name).plateField()
                        temperature($preset.extruder)
                        temperature($preset.bed)
                        Button { presets.removeAll { $0.id == preset.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.plateQuiet)
                            .controlSize(.small)
                            .help("Remove this preset")
                    }
                }
            }
            Button {
                presets.append(TemperaturePresetDraft(name: "", extruder: 210, bed: 60))
            } label: {
                Label("Add a preset", systemImage: "plus")
            }
            .buttonStyle(.plateQuiet)
            .controlSize(.small)
        } save: {
            session.saveTemperaturePresets(presets)
            dismiss()
        }
    }

    private func temperature(_ value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            TextField("", value: value, format: .number.precision(.fractionLength(0)))
                .plateField()
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
            Text(verbatim: "°C").font(Typeface.caption).foregroundStyle(Palette.faint)
        }
    }
}

/// The layout every settings sheet here shares: a title, a line about it, the fields, then Cancel and Save.
struct SettingsSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let intro: LocalizedStringKey
    var canSave = true
    @ViewBuilder var content: Content
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Typeface.title).foregroundStyle(Palette.paper)
                Text(intro).font(Typeface.body).foregroundStyle(Palette.dust).fixedSize(horizontal: false, vertical: true)
            }
            content
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plateQuiet).keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.plate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(26)
        .frame(width: 520)
        .background(Palette.extrusion)
    }
}

// MARK: - Printer profiles

/// A printer profile's size, bed and nozzle: what OctoPrint uses to check prints fit and draw them.
struct PrinterProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    /// The profile being changed, or nil for a new one.
    let profile: PrinterProfile?
    @State private var draft: PrinterProfileDraft
    @State private var confirmingDelete = false

    init(session: PrinterSession, profile: PrinterProfile?) {
        self.session = session
        self.profile = profile
        _draft = State(initialValue: PrinterProfileDraft(profile ?? session.currentProfile, asNew: profile == nil))
    }

    private var canDelete: Bool { profile != nil && profile?.default != true && profile?.current != true }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile == nil ? "New printer profile" : "Printer profile").font(Typeface.title).foregroundStyle(Palette.paper)
                Text(profile == nil
                     ? "Starts from the current profile. OctoPrint uses it to check prints fit, and to draw them."
                     : "OctoPrint uses this to check prints fit, and to draw them. Changes apply from the next print.")
                    .font(Typeface.body).foregroundStyle(Palette.dust).fixedSize(horizontal: false, vertical: true)
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    label("Name")
                    TextField("For example, Workshop MK3S", text: $draft.name).plateField()
                }
                GridRow {
                    label("Model")
                    TextField("For example, Original Prusa MK3S+", text: $draft.model).plateField()
                }
                GridRow {
                    label("Build volume")
                    HStack(spacing: 6) {
                        number($draft.width, help: "Width")
                        Text(verbatim: "×").foregroundStyle(Palette.faint)
                        number($draft.depth, help: "Depth")
                        Text(verbatim: "×").foregroundStyle(Palette.faint)
                        number($draft.height, help: "Height")
                        Text(verbatim: "mm").font(Typeface.caption).foregroundStyle(Palette.faint)
                    }
                }
                GridRow {
                    label("Bed")
                    HStack(spacing: 10) {
                        PlateMenu(selection: $draft.round, options: [(false, String(localized: "Rectangular")), (true, String(localized: "Round"))])
                        PlateMenu(selection: $draft.originCentre, options: [(false, String(localized: "Zero at the front left")),
                                                                            (true, String(localized: "Zero in the centre"))])
                    }
                }
                GridRow {
                    label("Nozzle")
                    HStack(spacing: 6) {
                        number($draft.nozzle, help: "Nozzle diameter", digits: 2)
                        Text(verbatim: "mm").font(Typeface.caption).foregroundStyle(Palette.faint)
                        Spacer().frame(width: 16)
                        Stepper(value: $draft.extruders, in: 1...8) {
                            Text("\(draft.extruders) extruders").font(Typeface.body).foregroundStyle(Palette.paper)
                        }
                    }
                }
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    VStack(alignment: .leading, spacing: 8) {
                        toggle("Heated bed", isOn: $draft.heatedBed)
                        toggle("Heated chamber", isOn: $draft.heatedChamber)
                        if draft.extruders > 1 { toggle("The extruders share one nozzle", isOn: $draft.sharedNozzle) }
                    }
                }
            }

            HStack {
                if canDelete {
                    Button("Delete…", role: .destructive) { confirmingDelete = true }
                        .buttonStyle(.plateQuiet)
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plateQuiet).keyboardShortcut(.cancelAction)
                Button(profile == nil ? "Add" : "Save") {
                    session.saveProfile(draft)
                    dismiss()
                }
                .buttonStyle(.plate)
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid)
            }
        }
        .padding(26)
        .frame(width: 580)
        .background(Palette.extrusion)
        .sheet(isPresented: $confirmingDelete) {
            if let profile {
                ConfirmSheet(symbol: "trash", title: "Delete \(profile.name)?", message: "The profile is removed from OctoPrint. Printers using it switch to the default profile.",
                             confirmTitle: "Delete", onConfirm: {
                                 session.deleteProfile(profile)
                                 dismiss()
                             })
            }
        }
    }

    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.dust).gridColumnAlignment(.leading)
    }

    private func number(_ value: Binding<Double>, help: LocalizedStringKey, digits: Int = 0) -> some View {
        TextField("", value: value, format: .number.precision(.fractionLength(0...max(digits, 1))))
            .plateField()
            .multilineTextAlignment(.trailing)
            .frame(width: 70)
            .help(help)
    }

    private func toggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title).font(Typeface.body).foregroundStyle(Palette.paper) }
            .toggleStyle(.switch)
            .tint(Palette.accent)
            .controlSize(.small)
    }
}

// MARK: - Logs as they arrive

/// Lines from OctoPrint as they arrive, kept scrolled to the latest.
struct LiveLog: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(verbatim: line)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Palette.dust)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(12)
            }
            .onChange(of: lines.count) { _, count in
                if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
            .onAppear { if !lines.isEmpty { proxy.scrollTo(lines.count - 1, anchor: .bottom) } }
        }
        .machined(radius: 14, fill: Palette.graphite)
    }
}

// MARK: - Restoring a backup

/// A backup being restored: the upload, OctoPrint's log, then how it went. It can't be closed while it runs.
struct RestoreProgressSheet: View {
    let session: PrinterSession

    var body: some View {
        let restore = session.restore
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Group {
                    switch restore?.outcome {
                    case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.ready)
                    case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(Palette.hot)
                    case nil: ProgressView().controlSize(.small).tint(Palette.accent)
                    }
                }
                .font(.system(size: 20))
                .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(heading(restore)).font(Typeface.subhead).foregroundStyle(Palette.paper)
                    Text(verbatim: restore?.name ?? "").font(Typeface.caption).foregroundStyle(Palette.faint).lineLimit(1)
                }
            }
            if let upload = restore?.upload {
                ProgressView(value: upload).tint(Palette.accent)
            }
            switch restore?.outcome {
            case .done:
                Text("OctoPrint is restarting with the restored settings and plugins. OctoMac reconnects by itself.")
                    .font(Typeface.body).foregroundStyle(Palette.dust).fixedSize(horizontal: false, vertical: true)
            case .failed(let reason):
                Text(verbatim: reason).font(Typeface.body).foregroundStyle(Palette.hot).fixedSize(horizontal: false, vertical: true)
            case nil:
                EmptyView()
            }
            LiveLog(lines: restore?.log ?? [])
                .frame(height: 220)
            HStack {
                Spacer()
                Button("Done") { session.dismissRestore() }
                    .buttonStyle(.plate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(restore?.isRunning != false)
            }
        }
        .padding(26)
        .frame(width: 560)
        .background(Palette.extrusion)
        .interactiveDismissDisabled(restore?.isRunning == true)
    }

    private func heading(_ restore: BackupRestore?) -> LocalizedStringKey {
        switch restore?.outcome {
        case .done: "Backup restored"
        case .failed: "Couldn't restore the backup"
        case nil: restore?.upload != nil ? "Sending the backup to OctoPrint" : "Restoring the backup"
        }
    }
}
