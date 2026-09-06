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
        GCodeGroup(name: "Moving", entries: [
            GCodeEntry(code: "G28", title: "Home", detail: "Moves to the end stops so the printer knows where it is. Name axes to home only those, for example G28 X Y.", example: "G28"),
            GCodeEntry(code: "G28 W", title: "Home without levelling", detail: "Homes all axes but skips mesh bed levelling.", example: "G28 W", firmware: "Prusa"),
            GCodeEntry(code: "G0 / G1", title: "Move", detail: "Moves in a straight line. G0 is for travel, G1 for printing moves. F sets the speed in mm per minute.", example: "G1 X50 Y50 F3000"),
            GCodeEntry(code: "G90", title: "Absolute positions", detail: "Coordinates after this are positions on the bed.", example: "G90"),
            GCodeEntry(code: "G91", title: "Relative positions", detail: "Coordinates after this are distances from where the head is now. Handy for nudging, for example G91 then G1 Z5.", example: "G91"),
            GCodeEntry(code: "G92", title: "Set position", detail: "Tells the printer where it is without moving. G92 E0 resets the extruder count.", example: "G92 E0"),
            GCodeEntry(code: "M114", title: "Report position", detail: "Replies with the current X, Y, Z and E position.", example: "M114"),
            GCodeEntry(code: "G4", title: "Wait", detail: "Pauses for a time. S is seconds, P is milliseconds.", example: "G4 S5"),
            GCodeEntry(code: "M400", title: "Finish moves", detail: "Waits until every queued move has finished.", example: "M400"),
        ]),
        GCodeGroup(name: "Temperature", entries: [
            GCodeEntry(code: "M104", title: "Set hotend", detail: "Sets the hotend temperature and carries on straight away. S0 turns it off.", example: "M104 S215"),
            GCodeEntry(code: "M109", title: "Set hotend and wait", detail: "Sets the hotend temperature and waits until it gets there.", example: "M109 S215"),
            GCodeEntry(code: "M140", title: "Set bed", detail: "Sets the bed temperature and carries on straight away. S0 turns it off.", example: "M140 S60"),
            GCodeEntry(code: "M190", title: "Set bed and wait", detail: "Sets the bed temperature and waits until it gets there.", example: "M190 S60"),
            GCodeEntry(code: "M105", title: "Report temperatures", detail: "Replies with every heater's current and target temperature.", example: "M105"),
            GCodeEntry(code: "M155", title: "Report temperatures automatically", detail: "Sends temperatures every S seconds without being asked. S0 stops it.", example: "M155 S2"),
            GCodeEntry(code: "M108", title: "Stop waiting", detail: "Breaks out of a heating wait (M109 or M190), for example when a cancel is stuck behind one.", example: "M108"),
            GCodeEntry(code: "M303", title: "PID tune", detail: "Heats and cools the hotend (E0) or bed (E-1) a few times to tune its temperature control. C is the number of cycles.", example: "M303 E0 S215 C8"),
            GCodeEntry(code: "M301", title: "Set hotend PID", detail: "Sets the hotend's PID values by hand. Send with no values to see the current ones.", example: "M301"),
        ]),
        GCodeGroup(name: "Fans", entries: [
            GCodeEntry(code: "M106", title: "Part fan on", detail: "Sets the part cooling fan speed from 0 to 255.", example: "M106 S255"),
            GCodeEntry(code: "M107", title: "Part fan off", detail: "Turns the part cooling fan off.", example: "M107"),
        ]),
        GCodeGroup(name: "Filament and extrusion", entries: [
            GCodeEntry(code: "M600", title: "Change filament", detail: "Parks the head and walks you through swapping filament on the printer's screen.", example: "M600"),
            GCodeEntry(code: "M701", title: "Load filament", detail: "Loads filament into the hotend.", example: "M701"),
            GCodeEntry(code: "M702", title: "Unload filament", detail: "Unloads filament from the hotend. On an MMU, M702 C unloads the current slot.", example: "M702"),
            GCodeEntry(code: "T0 to T4", title: "Choose tool or MMU slot", detail: "Selects an extruder, or the filament slot on a Prusa MMU.", example: "T0"),
            GCodeEntry(code: "M82", title: "Absolute extrusion", detail: "E values after this are totals.", example: "M82"),
            GCodeEntry(code: "M83", title: "Relative extrusion", detail: "E values after this are amounts to push from now. Most slicers use this.", example: "M83"),
            GCodeEntry(code: "M220", title: "Print speed", detail: "Scales print speed as a percentage. Send with no value to see the current speed.", example: "M220 S100"),
            GCodeEntry(code: "M221", title: "Flow", detail: "Scales how much filament is pushed, as a percentage.", example: "M221 S100"),
            GCodeEntry(code: "M900", title: "Linear advance", detail: "Sets the pressure advance K factor, which sharpens corners.", example: "M900 K0.05"),
            GCodeEntry(code: "M92", title: "Steps per mm", detail: "Sets how far each motor moves per step. Send with no values to see them. Save with M500.", example: "M92"),
            GCodeEntry(code: "M302", title: "Allow cold extrusion", detail: "Lets the extruder move below its minimum temperature. Only for testing; it can grind filament.", example: "M302 S0"),
        ]),
        GCodeGroup(name: "Bed levelling", entries: [
            GCodeEntry(code: "G80", title: "Mesh bed levelling", detail: "Probes the bed in a grid and uses the result for the next print.", example: "G80", firmware: "Prusa"),
            GCodeEntry(code: "G81", title: "Show mesh", detail: "Prints the last measured bed mesh.", example: "G81", firmware: "Prusa"),
            GCodeEntry(code: "G29", title: "Auto bed levelling", detail: "Probes the bed and builds a levelling mesh.", example: "G29", firmware: "Marlin"),
            GCodeEntry(code: "M420", title: "Levelling on or off", detail: "S1 turns bed levelling on, S0 off. V shows the stored mesh.", example: "M420 S1 V", firmware: "Marlin"),
            GCodeEntry(code: "G30", title: "Probe once", detail: "Probes the bed at the current position and reports the height.", example: "G30", firmware: "Marlin"),
            GCodeEntry(code: "M851", title: "Probe offset", detail: "Sets the Z offset between the probe and the nozzle. Send with no values to see it.", example: "M851", firmware: "Marlin"),
        ]),
        GCodeGroup(name: "Motors", entries: [
            GCodeEntry(code: "M17", title: "Motors on", detail: "Powers the stepper motors so they hold their position.", example: "M17"),
            GCodeEntry(code: "M18 / M84", title: "Motors off", detail: "Releases the motors so you can move the head and bed by hand.", example: "M18"),
            GCodeEntry(code: "M119", title: "End stop status", detail: "Replies with whether each end stop is triggered.", example: "M119"),
        ]),
        GCodeGroup(name: "Printer information", entries: [
            GCodeEntry(code: "M115", title: "Firmware info", detail: "Replies with the firmware name, version and what it supports.", example: "M115"),
            GCodeEntry(code: "M503", title: "Show settings", detail: "Lists the settings the printer is using right now.", example: "M503"),
            GCodeEntry(code: "M27", title: "SD print status", detail: "Reports progress when printing from the printer's own SD card.", example: "M27"),
            GCodeEntry(code: "M31", title: "Print time", detail: "Reports how long the current print has been running.", example: "M31"),
            GCodeEntry(code: "M78", title: "Print statistics", detail: "Reports total prints, print time and filament used.", example: "M78"),
        ]),
        GCodeGroup(name: "Settings", entries: [
            GCodeEntry(code: "M500", title: "Save settings", detail: "Saves the current settings so they survive a restart.", example: "M500"),
            GCodeEntry(code: "M501", title: "Load saved settings", detail: "Goes back to the last saved settings.", example: "M501"),
            GCodeEntry(code: "M502", title: "Factory settings", detail: "Loads the firmware's defaults. Send M500 afterwards to keep them.", example: "M502"),
            GCodeEntry(code: "M201", title: "Max acceleration", detail: "Sets the maximum acceleration for each axis, in mm per second squared.", example: "M201"),
            GCodeEntry(code: "M203", title: "Max speed", detail: "Sets the maximum speed for each axis, in mm per second.", example: "M203"),
            GCodeEntry(code: "M204", title: "Acceleration", detail: "Sets the acceleration for printing (P), retracting (R) and travel (T).", example: "M204"),
        ]),
        GCodeGroup(name: "Print control", entries: [
            GCodeEntry(code: "M0 / M1", title: "Pause for the user", detail: "Stops until someone presses the printer's knob or button.", example: "M0"),
            GCodeEntry(code: "M24", title: "Start or resume SD print", detail: "Starts or resumes printing from the printer's own SD card.", example: "M24"),
            GCodeEntry(code: "M25", title: "Pause SD print", detail: "Pauses printing from the printer's own SD card.", example: "M25"),
            GCodeEntry(code: "M117", title: "Show a message", detail: "Writes a message on the printer's screen.", example: "M117 Hello from OctoMac"),
            GCodeEntry(code: "M300", title: "Beep", detail: "Plays a tone. S is the pitch in hertz, P the length in milliseconds.", example: "M300 S440 P200"),
            GCodeEntry(code: "M73", title: "Set progress", detail: "Sets the progress shown on the printer's screen, in percent.", example: "M73 P50"),
            GCodeEntry(code: "M112", title: "Emergency stop", detail: "Stops everything at once. The printer must be reset and reconnected afterwards.", example: "M112"),
            GCodeEntry(code: "M999", title: "Restart after an error", detail: "Clears an error stop so the printer accepts commands again.", example: "M999"),
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
