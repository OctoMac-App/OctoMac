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
    @State private var confirmingKey: KeyChange?

    private enum KeyChange: Identifiable {
        case make, remove
        var id: Self { self }
    }

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
                if !session.globalAPIKeyRetired { globalKeyRow }
            }
        }
        .sheet(isPresented: $editingCamera) { CameraSettingsSheet(session: session) }
        .sheet(isPresented: $editingPresets) { TemperaturePresetsSheet(session: session) }
        .sheet(item: $confirmingKey) { change in
            switch change {
            case .make:
                ConfirmSheet(symbol: "key", tint: Palette.warm, title: "Make a new global API key?",
                             message: "It replaces the old one, so anything using that stops working. The new key is copied to the clipboard rather than shown. It gives full control of OctoPrint, so keep it private.",
                             confirmTitle: "Make and copy", onConfirm: { session.makeGlobalAPIKey() })
            case .remove:
                ConfirmSheet(symbol: "key", title: "Remove the global API key?",
                             message: "Anything still using it stops working. Apps that asked for their own key, like OctoMac, keep working.",
                             confirmTitle: "Remove", onConfirm: { session.removeGlobalAPIKey() })
            }
        }
    }

    /// OctoPrint's old single key for the whole server. Apps now ask for their own, so most people don't need one.
    private var globalKeyRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "key").foregroundStyle(Palette.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Global API key").font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                Text(session.usesGlobalAPIKey ? "OctoMac signs in with it, so it can't be changed here."
                     : session.globalAPIKey == nil ? "None. Apps ask for their own key instead." : "Set. It gives full control of OctoPrint to anything that has it.")
                    .font(Typeface.caption).foregroundStyle(Palette.faint).lineLimit(2)
            }
            Spacer()
            if session.globalAPIKey != nil {
                Button("Remove…") { confirmingKey = .remove }
                    .buttonStyle(.plateQuiet)
                    .controlSize(.small)
                    .disabled(session.usesGlobalAPIKey)
            }
            Button(session.globalAPIKey == nil ? "Make one…" : "New key…") { confirmingKey = .make }
                .buttonStyle(.plateQuiet)
                .controlSize(.small)
                .disabled(session.usesGlobalAPIKey)
        }
        .padding(12)
        .machined(radius: 12, fill: Palette.graphite)
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
    @State private var testing = false
    /// The result of the last test, for the address it was made with.
    @State private var test: (address: String, check: AddressCheck?)?

    init(session: PrinterSession) {
        self.session = session
        _camera = State(initialValue: session.cameraSettings)
    }

    var body: some View {
        SettingsSheet(title: "Camera", intro: "Where OctoPrint finds the camera's video and still pictures. Addresses starting with / are on the Raspberry Pi itself.") {
            field("Video stream", text: $camera.stream, prompt: "/webcam/?action=stream")
            field("Still picture", text: $camera.snapshot, prompt: "http://127.0.0.1:8080/?action=snapshot")
            snapshotTest
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

    /// OctoPrint fetches the still picture itself, so this checks the address as the Raspberry Pi sees it.
    private var snapshotTest: some View {
        let address = camera.snapshot.trimmingCharacters(in: .whitespaces)
        let result = test?.address == address ? test : nil
        return HStack(alignment: .center, spacing: 12) {
            Button {
                testing = true
                Task {
                    let check = await session.checkSnapshot(address)
                    test = (address, check)
                    testing = false
                }
            } label: {
                if testing { ProgressView().controlSize(.small) } else { Label("Test", systemImage: "camera.viewfinder") }
            }
            .buttonStyle(.plateQuiet)
            .controlSize(.small)
            .disabled(testing || !(address.hasPrefix("http://") || address.hasPrefix("https://")))
            .help("OctoPrint fetches a picture from this address, as the Raspberry Pi sees it")

            if let result {
                if let check = result.check, check.ok {
                    if let data = check.content, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    Label("OctoPrint can get a picture from the camera.", systemImage: "checkmark.circle.fill")
                        .font(Typeface.caption).foregroundStyle(Palette.ready)
                } else {
                    Label(result.check.map { $0.status > 0 ? String(localized: "OctoPrint couldn't get a picture from that address (it answered \($0.status)).")
                                                           : String(localized: "OctoPrint couldn't reach that address.") }
                          ?? String(localized: "OctoPrint couldn't reach that address."),
                          systemImage: "xmark.octagon.fill")
                        .font(Typeface.caption).foregroundStyle(Palette.hot)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if !address.isEmpty, !(address.hasPrefix("http://") || address.hasPrefix("https://")) {
                Text("OctoPrint needs a full address for still pictures, starting with http://.")
                    .font(Typeface.caption).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
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

// MARK: - File Check

/// What OctoPrint's File Check found in a file, in plain words, with a link to OctoPrint's advice.
struct FileProblems: View {
    let problems: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(problems, id: \.self) { problem in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warm)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.describe(problem)).font(Typeface.caption).foregroundStyle(Palette.paper)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = FileCheck.helpURL(for: problem) {
                            Link("What to do about it", destination: url).font(Typeface.caption).foregroundStyle(Palette.accent)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.warm.opacity(0.1)))
    }

    static func describe(_ problem: String) -> String {
        switch problem {
        case "travel_speed":
            String(localized: "The slicer left a placeholder in this file that was never filled in, so the printer may move at the wrong speed. Slice it again with an up-to-date slicer.")
        case "leaked_api_key":
            String(localized: "The slicer wrote an OctoPrint API key into this file. Anyone you share it with could control your printer. Turn that off in the slicer, slice again, and make a new key.")
        default:
            String(localized: "OctoPrint found a problem in this file (\(problem)).")
        }
    }
}

// MARK: - Plugin leftovers

/// Settings and data left behind by plugins that have been uninstalled. Removing them takes effect after a restart.
struct PluginLeftoversSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clean up after old plugins").font(Typeface.title).foregroundStyle(Palette.paper)
                Text("Uninstalling a plugin can leave its settings and data behind. Removing them tidies OctoPrint up, and takes effect after a restart.")
                    .font(Typeface.body).foregroundStyle(Palette.dust).fixedSize(horizontal: false, vertical: true)
            }
            if let leftovers = session.pluginLeftovers {
                if leftovers.isEmpty {
                    Label("Nothing to clean up.", systemImage: "checkmark.circle.fill")
                        .font(Typeface.bodyStrong).foregroundStyle(Palette.ready)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(leftovers) { leftover in
                                HStack(spacing: 12) {
                                    Image(systemName: "puzzlepiece.extension").foregroundStyle(Palette.dust).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: leftover.key).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                                        Text(describe(leftover)).font(Typeface.caption).foregroundStyle(Palette.faint)
                                    }
                                    Spacer()
                                    Button("Remove") { session.cleanUpLeftovers(leftover.key) }
                                        .buttonStyle(.plateQuiet)
                                        .controlSize(.small)
                                }
                                .padding(10)
                                .machined(radius: 10, fill: Palette.graphite)
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
            } else {
                ProgressView().controlSize(.small).tint(Palette.accent)
            }
            HStack {
                if (session.pluginLeftovers?.count ?? 0) > 1 {
                    Button("Remove all") { session.cleanUpLeftovers(nil) }.buttonStyle(.plateQuiet)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.plate).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 520)
        .background(Palette.extrusion)
        .task { await session.refreshPluginLeftovers() }
    }

    private func describe(_ leftover: PluginLeftovers) -> LocalizedStringKey {
        switch (leftover.settings, leftover.data) {
        case (true, true): "Settings and data"
        case (true, false): "Settings"
        case (false, true): "Data"
        default: "An entry in the list of switched-off plugins"
        }
    }
}

// MARK: - Logging

/// How much each part of OctoPrint writes to its log, and whether the conversation with the printer is logged.
struct LoggingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    @State private var levels: [String: String] = [:]
    @State private var adding = ""

    private static let choices: [(String, String)] = [
        ("DEBUG", String(localized: "Everything (debug)")), ("INFO", String(localized: "Normal")),
        ("WARNING", String(localized: "Warnings and errors")), ("ERROR", String(localized: "Errors only")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How much to log").font(Typeface.title).foregroundStyle(Palette.paper)
                Text("While finding a fault, OctoPrint can log more detail from the part that's misbehaving. Set it back afterwards, since detailed logs grow quickly.")
                    .font(Typeface.body).foregroundStyle(Palette.dust).fixedSize(horizontal: false, vertical: true)
            }
            if let logging = session.logging {
                Toggle(isOn: Binding(get: { session.logging?.serialLog ?? false }, set: { session.setSerialLog($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log the conversation with the printer").font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                        Text("Saved as serial.log. Useful when the printer misbehaves; slows OctoPrint a little.")
                            .font(Typeface.caption).foregroundStyle(Palette.faint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .tint(Palette.accent)
                .controlSize(.small)
                .padding(12)
                .machined(radius: 12, fill: Palette.graphite)

                VStack(spacing: 6) {
                    ForEach(levels.keys.sorted(), id: \.self) { logger in
                        HStack(spacing: 10) {
                            Text(verbatim: logger).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.paper)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            PlateMenu(selection: Binding(get: { levels[logger] ?? "INFO" }, set: { levels[logger] = $0 }), options: Self.choices)
                                .frame(width: 200)
                            Button { levels[logger] = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plateQuiet)
                                .controlSize(.small)
                                .help("Back to normal")
                        }
                    }
                    let others = logging.available.filter { levels[$0] == nil }
                    if !others.isEmpty {
                        HStack(spacing: 10) {
                            PlateMenu(selection: $adding, options: [("", String(localized: "Choose a part of OctoPrint…"))] + others.map { ($0, $0) })
                            Button("Add") {
                                levels[adding] = "DEBUG"
                                adding = ""
                            }
                            .buttonStyle(.plateQuiet)
                            .controlSize(.small)
                            .disabled(adding.isEmpty)
                        }
                    }
                }
            } else {
                ProgressView().controlSize(.small).tint(Palette.accent)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plateQuiet).keyboardShortcut(.cancelAction)
                Button("Save") {
                    session.saveLoggingLevels(levels)
                    dismiss()
                }
                .buttonStyle(.plate)
                .keyboardShortcut(.defaultAction)
                .disabled(session.logging == nil || levels == session.logging?.levels)
            }
        }
        .padding(26)
        .frame(width: 580)
        .background(Palette.extrusion)
        .task {
            await session.refreshLogging()
            levels = session.logging?.levels ?? [:]
        }
    }
}
