import SwiftUI

/// One entry in the G-code cheat sheet.
struct GCodeEntry: Identifiable, Hashable {
    let code: String
    let title: String
    let detail: String
    /// What goes into the console when you pick it.
    let example: String
    /// Set when only some firmware understands it.
    var firmware: String?

    var id: String { code }
}

struct GCodeGroup: Identifiable {
    let name: String
    let entries: [GCodeEntry]
    var id: String { name }
}

/// Common commands for Marlin and Prusa firmware, in plain words.
enum GCodeReference {
    static let groups: [GCodeGroup] = [
        GCodeGroup(name: String(localized: "Moving"), entries: [
            GCodeEntry(code: "G28", title: String(localized: "Home"), detail: String(localized: "Moves to the end stops so the printer knows where it is. Name axes to home only those, for example G28 X Y."), example: "G28"),
            GCodeEntry(code: "G28 W", title: String(localized: "Home without levelling"), detail: String(localized: "Homes all axes but skips mesh bed levelling."), example: "G28 W", firmware: "Prusa"),
            GCodeEntry(code: "G0 / G1", title: String(localized: "Move"), detail: String(localized: "Moves in a straight line. G0 is for travel, G1 for printing moves. F sets the speed in mm per minute."), example: "G1 X50 Y50 F3000"),
            GCodeEntry(code: "G90", title: String(localized: "Absolute positions"), detail: String(localized: "Coordinates after this are positions on the bed."), example: "G90"),
            GCodeEntry(code: "G91", title: String(localized: "Relative positions"), detail: String(localized: "Coordinates after this are distances from where the head is now. Handy for nudging, for example G91 then G1 Z5."), example: "G91"),
            GCodeEntry(code: "G92", title: String(localized: "Set position"), detail: String(localized: "Tells the printer where it is without moving. G92 E0 resets the extruder count."), example: "G92 E0"),
            GCodeEntry(code: "M114", title: String(localized: "Report position"), detail: String(localized: "Replies with the current X, Y, Z and E position."), example: "M114"),
            GCodeEntry(code: "G4", title: String(localized: "Wait"), detail: String(localized: "Pauses for a time. S is seconds, P is milliseconds."), example: "G4 S5"),
            GCodeEntry(code: "M400", title: String(localized: "Finish moves"), detail: String(localized: "Waits until every queued move has finished."), example: "M400"),
        ]),
        GCodeGroup(name: String(localized: "Temperature"), entries: [
            GCodeEntry(code: "M104", title: String(localized: "Set hotend"), detail: String(localized: "Sets the hotend temperature and carries on straight away. S0 turns it off."), example: "M104 S215"),
            GCodeEntry(code: "M109", title: String(localized: "Set hotend and wait"), detail: String(localized: "Sets the hotend temperature and waits until it gets there."), example: "M109 S215"),
            GCodeEntry(code: "M140", title: String(localized: "Set bed"), detail: String(localized: "Sets the bed temperature and carries on straight away. S0 turns it off."), example: "M140 S60"),
            GCodeEntry(code: "M190", title: String(localized: "Set bed and wait"), detail: String(localized: "Sets the bed temperature and waits until it gets there."), example: "M190 S60"),
            GCodeEntry(code: "M105", title: String(localized: "Report temperatures"), detail: String(localized: "Replies with every heater's current and target temperature."), example: "M105"),
            GCodeEntry(code: "M155", title: String(localized: "Report temperatures automatically"), detail: String(localized: "Sends temperatures every S seconds without being asked. S0 stops it."), example: "M155 S2"),
            GCodeEntry(code: "M108", title: String(localized: "Stop waiting"), detail: String(localized: "Breaks out of a heating wait (M109 or M190), for example when a cancel is stuck behind one."), example: "M108"),
            GCodeEntry(code: "M303", title: String(localized: "PID tune"), detail: String(localized: "Heats and cools the hotend (E0) or bed (E-1) a few times to tune its temperature control. C is the number of cycles."), example: "M303 E0 S215 C8"),
            GCodeEntry(code: "M301", title: String(localized: "Set hotend PID"), detail: String(localized: "Sets the hotend's PID values by hand. Send with no values to see the current ones."), example: "M301"),
        ]),
        GCodeGroup(name: String(localized: "Fans"), entries: [
            GCodeEntry(code: "M106", title: String(localized: "Part fan on"), detail: String(localized: "Sets the part cooling fan speed from 0 to 255."), example: "M106 S255"),
            GCodeEntry(code: "M107", title: String(localized: "Part fan off"), detail: String(localized: "Turns the part cooling fan off."), example: "M107"),
        ]),
        GCodeGroup(name: String(localized: "Filament and extrusion"), entries: [
            GCodeEntry(code: "M600", title: String(localized: "Change filament"), detail: String(localized: "Parks the head and walks you through swapping filament on the printer's screen."), example: "M600"),
            GCodeEntry(code: "M701", title: String(localized: "Load filament"), detail: String(localized: "Loads filament into the hotend."), example: "M701"),
            GCodeEntry(code: "M702", title: String(localized: "Unload filament"), detail: String(localized: "Unloads filament from the hotend. On an MMU, M702 C unloads the current slot."), example: "M702"),
            GCodeEntry(code: "T0, T1, T2…", title: String(localized: "Choose tool or MMU slot"), detail: String(localized: "Selects an extruder, or the filament slot on a Prusa MMU."), example: "T0"),
            GCodeEntry(code: "M82", title: String(localized: "Absolute extrusion"), detail: String(localized: "E values after this are totals."), example: "M82"),
            GCodeEntry(code: "M83", title: String(localized: "Relative extrusion"), detail: String(localized: "E values after this are amounts to push from now. Most slicers use this."), example: "M83"),
            GCodeEntry(code: "M220", title: String(localized: "Print speed"), detail: String(localized: "Scales print speed as a percentage. Send with no value to see the current speed."), example: "M220 S100"),
            GCodeEntry(code: "M221", title: String(localized: "Flow"), detail: String(localized: "Scales how much filament is pushed, as a percentage."), example: "M221 S100"),
            GCodeEntry(code: "M900", title: String(localized: "Linear advance"), detail: String(localized: "Sets the pressure advance K factor, which sharpens corners."), example: "M900 K0.05"),
            GCodeEntry(code: "M92", title: String(localized: "Steps per mm"), detail: String(localized: "Sets how far each motor moves per step. Send with no values to see them. Save with M500."), example: "M92"),
            GCodeEntry(code: "M302", title: String(localized: "Allow cold extrusion"), detail: String(localized: "Lets the extruder move below its minimum temperature. Only for testing; it can grind filament."), example: "M302 S0"),
        ]),
        GCodeGroup(name: String(localized: "Bed levelling"), entries: [
            GCodeEntry(code: "G80", title: String(localized: "Mesh bed levelling"), detail: String(localized: "Probes the bed in a grid and uses the result for the next print."), example: "G80", firmware: "Prusa"),
            GCodeEntry(code: "G81", title: String(localized: "Show mesh"), detail: String(localized: "Prints the last measured bed mesh."), example: "G81", firmware: "Prusa"),
            GCodeEntry(code: "G29", title: String(localized: "Auto bed levelling"), detail: String(localized: "Probes the bed and builds a levelling mesh."), example: "G29", firmware: "Marlin"),
            GCodeEntry(code: "M420", title: String(localized: "Levelling on or off"), detail: String(localized: "S1 turns bed levelling on, S0 off. V shows the stored mesh."), example: "M420 S1 V", firmware: "Marlin"),
            GCodeEntry(code: "G30", title: String(localized: "Probe once"), detail: String(localized: "Probes the bed at the current position and reports the height."), example: "G30", firmware: "Marlin"),
            GCodeEntry(code: "M851", title: String(localized: "Probe offset"), detail: String(localized: "Sets the Z offset between the probe and the nozzle. Send with no values to see it."), example: "M851", firmware: "Marlin"),
        ]),
        GCodeGroup(name: String(localized: "Motors"), entries: [
            GCodeEntry(code: "M17", title: String(localized: "Motors on"), detail: String(localized: "Powers the stepper motors so they hold their position."), example: "M17"),
            GCodeEntry(code: "M18 / M84", title: String(localized: "Motors off"), detail: String(localized: "Releases the motors so you can move the head and bed by hand."), example: "M18"),
            GCodeEntry(code: "M119", title: String(localized: "End stop status"), detail: String(localized: "Replies with whether each end stop is triggered."), example: "M119"),
        ]),
        GCodeGroup(name: String(localized: "Printer information"), entries: [
            GCodeEntry(code: "M115", title: String(localized: "Firmware info"), detail: String(localized: "Replies with the firmware name, version and what it supports."), example: "M115"),
            GCodeEntry(code: "M503", title: String(localized: "Show settings"), detail: String(localized: "Lists the settings the printer is using right now."), example: "M503"),
            GCodeEntry(code: "M27", title: String(localized: "SD print status"), detail: String(localized: "Reports progress when printing from the printer's own SD card."), example: "M27"),
            GCodeEntry(code: "M31", title: String(localized: "Print time"), detail: String(localized: "Reports how long the current print has been running."), example: "M31"),
            GCodeEntry(code: "M78", title: String(localized: "Print statistics"), detail: String(localized: "Reports total prints, print time and filament used."), example: "M78"),
        ]),
        GCodeGroup(name: String(localized: "Settings"), entries: [
            GCodeEntry(code: "M500", title: String(localized: "Save settings"), detail: String(localized: "Saves the current settings so they survive a restart."), example: "M500"),
            GCodeEntry(code: "M501", title: String(localized: "Load saved settings"), detail: String(localized: "Goes back to the last saved settings."), example: "M501"),
            GCodeEntry(code: "M502", title: String(localized: "Factory settings"), detail: String(localized: "Loads the firmware's defaults. Send M500 afterwards to keep them."), example: "M502"),
            GCodeEntry(code: "M201", title: String(localized: "Max acceleration"), detail: String(localized: "Sets the maximum acceleration for each axis, in mm per second squared."), example: "M201"),
            GCodeEntry(code: "M203", title: String(localized: "Max speed"), detail: String(localized: "Sets the maximum speed for each axis, in mm per second."), example: "M203"),
            GCodeEntry(code: "M204", title: String(localized: "Acceleration"), detail: String(localized: "Sets the acceleration for printing (P), retracting (R) and travel (T)."), example: "M204"),
        ]),
        GCodeGroup(name: String(localized: "Print control"), entries: [
            GCodeEntry(code: "M0 / M1", title: String(localized: "Pause for the user"), detail: String(localized: "Stops until someone presses the printer's knob or button."), example: "M0"),
            GCodeEntry(code: "M24", title: String(localized: "Start or resume SD print"), detail: String(localized: "Starts or resumes printing from the printer's own SD card."), example: "M24"),
            GCodeEntry(code: "M25", title: String(localized: "Pause SD print"), detail: String(localized: "Pauses printing from the printer's own SD card."), example: "M25"),
            GCodeEntry(code: "M117", title: String(localized: "Show a message"), detail: String(localized: "Writes a message on the printer's screen."), example: "M117 Hello from OctoMac"),
            GCodeEntry(code: "M300", title: String(localized: "Beep"), detail: String(localized: "Plays a tone. S is the pitch in hertz, P the length in milliseconds."), example: "M300 S440 P200"),
            GCodeEntry(code: "M73", title: String(localized: "Set progress"), detail: String(localized: "Sets the progress shown on the printer's screen, in percent."), example: "M73 P50"),
            GCodeEntry(code: "M112", title: String(localized: "Emergency stop"), detail: String(localized: "Stops everything at once. The printer must be reset and reconnected afterwards."), example: "M112"),
            GCodeEntry(code: "M999", title: String(localized: "Restart after an error"), detail: String(localized: "Clears an error stop so the printer accepts commands again."), example: "M999"),
        ]),
    ]
}

/// The cheat sheet beside the console. Picking a command puts its example in the input box, ready to edit and send.
struct GCodeReferencePanel: View {
    let pick: (GCodeEntry) -> Void
    let close: () -> Void
    @State private var search = ""

    private var filtered: [GCodeGroup] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return GCodeReference.groups }
        return GCodeReference.groups.compactMap { group in
            let entries = group.entries.filter {
                $0.code.lowercased().contains(query) || $0.title.lowercased().contains(query) || $0.detail.lowercased().contains(query)
            }
            return entries.isEmpty ? nil : GCodeGroup(name: group.name, entries: entries)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("G-code cheat sheet").font(Typeface.subhead).foregroundStyle(Palette.paper)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(.plateQuiet)
                    .controlSize(.small)
                    .help("Hide the cheat sheet")
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
                TextField("Search, for example \"fan\" or M600", text: $search)
                    .textFieldStyle(.plain)
                    .font(Typeface.body)
                    .foregroundStyle(Palette.paper)
                ClearFieldButton(text: $search)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Palette.graphite))
            .overlay(Capsule().strokeBorder(Palette.edge, lineWidth: 1))
            .padding(16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                    ForEach(filtered) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                GCodeRow(entry: entry) { pick(entry) }
                            }
                        } header: {
                            Text(group.name)
                                .font(Typeface.caption).foregroundStyle(Palette.faint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Palette.extrusion)
                        }
                    }
                    if filtered.isEmpty {
                        Text("Nothing matches. OctoPrint's console accepts any command your firmware knows.")
                            .font(Typeface.caption).foregroundStyle(Palette.faint)
                            .padding(16)
                    }
                }
                .padding(.bottom, 12)
            }

            Text("Click a command to put it in the box below the console. Nothing is sent until you press Send.")
                .font(Typeface.caption).foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
        }
        .frame(width: 340)
        .machined(radius: 20)
    }
}

private struct GCodeRow: View {
    let entry: GCodeEntry
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(entry.code).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(Palette.accent)
                    Text(entry.title).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                    Spacer(minLength: 0)
                    if let firmware = entry.firmware {
                        Text(firmware)
                            .font(Typeface.text(10, .demibold))
                            .foregroundStyle(Palette.dust)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Palette.graphite))
                    }
                }
                Text(entry.detail).font(Typeface.caption).foregroundStyle(Palette.dust)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Palette.extrusionHi : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
        .help("Put \(entry.example) in the command box")
    }
}
