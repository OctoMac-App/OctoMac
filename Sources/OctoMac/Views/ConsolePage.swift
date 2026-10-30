import OctoPrintKit
import SwiftUI

// MARK: - Console

struct ConsolePage: View {
    let session: PrinterSession
    /// Names of the filters that are switched on, one per line. Empty until you change something.
    @AppStorage("terminal.filters") private var enabledStorage = ""
    @AppStorage("terminal.hideTemperature") private var legacyHideTemperature = true
    @AppStorage("terminal.hideSD") private var legacyHideSD = true
    @State private var command = ""
    @State private var history: [String] = []
    @State private var historyIndex: Int?
    @State private var choosingFilters = false
    @State private var choosingHighlights = false
    /// Words and phrases to highlight, one per line.
    @AppStorage("terminal.highlights") private var highlightStorage = ""
    @AppStorage("terminal.highlightReplies") private var highlightReplies = true
    /// Commands sent from this console, so their replies can be picked out.
    @State private var sentHere: [String] = []
    @AppStorage("console.cheatSheet") private var showingCheatSheet = false
    @FocusState private var commandFocused: Bool
    /// While you're scrolled up reading, the console holds still: this is what's on screen, and new lines wait.
    @State private var frozen: [(offset: Int, element: String)]?
    @State private var frozenAt = 0
    @State private var atBottom = true
    @State private var userScrolling = false
    /// The saved command being added or changed.
    @State private var editingCommand: PrinterJournal.SavedCommand?

    private var filters: [TerminalFilter] {
        var list = TerminalFilter.fromSettings(session.settings)
        // An MMU chats with the printer constantly; worth a switch of its own.
        if session.mmu != nil { list.append(TerminalFilter.mmu) }
        return list
    }

    private var enabled: Set<String> {
        if enabledStorage.isEmpty {
            // Before this setting existed there were two switches; start from those.
            var names: Set<String> = []
            if legacyHideTemperature { names.insert("Suppress temperature messages") }
            if legacyHideSD { names.insert("Suppress SD status messages") }
            return names
        }
        return Set(enabledStorage.split(separator: "\n").map(String.init).filter { $0 != "-" })
    }

    private func setEnabled(_ name: String, _ on: Bool) {
        var names = enabled
        if on { names.insert(name) } else { names.remove(name) }
        // "-" keeps the setting non-empty when everything is switched off.
        enabledStorage = (["-"] + names.sorted()).joined(separator: "\n")
    }

    private var visible: (lines: [(offset: Int, element: String)], hidden: Int) {
        let active = filters.filter { enabled.contains($0.name) }
        let all = Array(session.terminal.enumerated())
        guard !active.isEmpty else { return (all, 0) }
        let shown = all.filter { _, line in !active.contains { $0.matches(line) } }
        return (shown, all.count - shown.count)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            conversation
            if showingCheatSheet {
                GCodeReferencePanel { entry in
                    command = entry.example
                    commandFocused = true
                } close: {
                    withAnimation(.snappy) { showingCheatSheet = false }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var conversation: some View {
        let visible = self.visible
        let activeCount = filters.filter { enabled.contains($0.name) }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Printer conversation").font(Typeface.subhead).foregroundStyle(Palette.paper)
                    .lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
                Spacer()
                if visible.hidden > 0 {
                    Text("\(visible.hidden) of \(session.terminal.count) lines hidden")
                        .font(Typeface.caption).foregroundStyle(Palette.faint)
                }
                Button { choosingFilters.toggle() } label: {
                    Label(activeCount == 0 ? "Hide messages" : "Hiding \(activeCount) kinds",
                          systemImage: "line.3.horizontal.decrease")
                }
                .buttonStyle(.plateQuiet)
                .controlSize(.small)
                .popover(isPresented: $choosingFilters, arrowEdge: .bottom) {
                    TerminalFilterList(filters: filters, enabled: enabled, toggle: setEnabled)
                }
                Button { choosingHighlights.toggle() } label: {
                    Label(highlightTerms.isEmpty ? "Highlight" : "Highlighting \(highlightTerms.count)", systemImage: "highlighter")
                }
                .buttonStyle(.plateQuiet)
                .controlSize(.small)
                .popover(isPresented: $choosingHighlights, arrowEdge: .bottom) {
                    ConsoleHighlightEditor(terms: highlightTerms, replies: $highlightReplies) { terms in
                        highlightStorage = terms.joined(separator: "\n")
                    }
                }
                Button { withAnimation(.snappy) { showingCheatSheet.toggle() } } label: {
                    Label("Cheat sheet", systemImage: "book.closed")
                }
                .buttonStyle(.plateQuiet)
                .controlSize(.small)
                .help("A list of common G-code commands and what they do")
            }
            .padding(20)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        let shown = frozen ?? visible.lines
                        let marks = highlights(for: shown)
                        ForEach(shown, id: \.offset) { offset, line in
                            ConsoleLine(line: line, highlight: marks[offset])
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 20)
                    .textSelection(.enabled)
                }
                .background(Palette.graphite)
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 24
                } action: { _, bottom in
                    atBottom = bottom
                    // Only your own scrolling pauses the console, not new lines arriving.
                    guard userScrolling else { return }
                    if bottom { frozen = nil } else if frozen == nil { pause(visible.lines) }
                }
                .onScrollPhaseChange { _, phase in
                    userScrolling = phase != .idle && phase != .animating
                    if phase == .idle, atBottom { frozen = nil }
                }
                .onChange(of: session.terminalReceived) { if frozen == nil { proxy.scrollTo("end", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                .overlay(alignment: .bottom) {
                    if frozen != nil {
                        let waiting = newVisibleLines
                        Button {
                            frozen = nil
                            withAnimation(.snappy) { proxy.scrollTo("end", anchor: .bottom) }
                        } label: {
                            Label(waiting > 0 ? "Paused while you read. \(waiting) new lines. Jump to latest" : "Paused while you read. Jump to latest",
                                  systemImage: "arrow.down")
                                .font(Typeface.text(12, .demibold))
                                .foregroundStyle(Palette.graphite)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Palette.accent))
                                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: frozen == nil)
            }

            savedCommands

            HStack(spacing: 10) {
                Text(verbatim: "›").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(Palette.accent)
                TextField("Send a G-code command, e.g. M115", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Palette.paper)
                    .focused($commandFocused)
                    .onSubmit(send)
                    .onKeyPress(.upArrow) { recall(-1) }
                    .onKeyPress(.downArrow) { recall(1) }
                ClearFieldButton(text: $command) { commandFocused = true }
                Button("Send", action: send)
                    .buttonStyle(.plate)
                    .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty || !session.flags.operational)
            }
            .padding(16)
        }
        .machined(radius: 20)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .sheet(item: $editingCommand) { command in
            SavedCommandSheet(command: command, isNew: !session.journal.commands.contains { $0.id == command.id }) { saved in
                session.saveCommand(saved)
            } remove: {
                session.removeCommand(command)
            }
        }
    }

    /// Your own one-click commands for this printer, above the command box.
    private var savedCommands: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(session.journal.commands) { saved in
                    Button { send(saved) } label: {
                        Label { Text(verbatim: saved.name) } icon: { Image(systemName: "play.fill") }
                            .lineLimit(1)
                    }
                    .buttonStyle(.plateQuiet)
                    .controlSize(.small)
                    .disabled(!session.flags.operational)
                    .help(Text(verbatim: saved.gcode))
                    .contextMenu {
                        Button("Edit…") { editingCommand = saved }
                        Button("Put in the command box") {
                            command = saved.gcode.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
                            commandFocused = true
                        }
                        Divider()
                        Button("Remove", role: .destructive) { session.removeCommand(saved) }
                    }
                }
                Button {
                    editingCommand = .init(name: "", gcode: command.trimmingCharacters(in: .whitespaces))
                } label: {
                    Label(session.journal.commands.isEmpty ? "Save a command as a button" : "Save a command", systemImage: "plus")
                        .lineLimit(1)
                }
                .buttonStyle(.plateQuiet)
                .controlSize(.small)
                .help("Keep a command you use often as a button here, for this printer. Right-click a button to change it.")
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 12)
    }

    private var highlightTerms: [String] {
        highlightStorage.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Which lines to tint: your own commands and the printer's replies to them, and lines with a highlighted word.
    private func highlights(for lines: [(offset: Int, element: String)]) -> [Int: Color] {
        var marks: [Int: Color] = [:]
        let terms = highlightTerms
        var inReply = false
        for (offset, line) in lines {
            if highlightReplies {
                if line.hasPrefix("Send:") {
                    inReply = sentHere.contains(Self.normalised(line))
                    if inReply { marks[offset] = Palette.accent }
                } else if inReply, line.hasPrefix("Recv:") {
                    marks[offset] = Palette.accent
                    // The reply ends at the printer's "ok".
                    if line.dropFirst(5).trimmingCharacters(in: .whitespaces).hasPrefix("ok") { inReply = false }
                }
            }
            if let index = terms.firstIndex(where: { line.localizedCaseInsensitiveContains($0) }) {
                marks[offset] = ConsoleHighlightEditor.color(at: index)
            }
        }
        return marks
    }

    /// "Send: N123 M114*45" and "m114" both become "M114".
    static func normalised(_ line: String) -> String {
        var text = line.hasPrefix("Send:") ? String(line.dropFirst(5)) : line
        text = text.trimmingCharacters(in: .whitespaces)
        if let match = text.firstMatch(of: /^N\d+\s+/) { text.removeSubrange(match.range) }
        if let star = text.lastIndex(of: "*") { text = String(text[..<star]) }
        return text.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// Lines that arrived since pausing and would actually be shown (not hidden by a filter).
    private var newVisibleLines: Int {
        let arrived = session.terminalReceived - frozenAt
        guard arrived > 0 else { return 0 }
        let active = filters.filter { enabled.contains($0.name) }
        return session.terminal.suffix(arrived).filter { line in !active.contains { $0.matches(line) } }.count
    }

    private func pause(_ lines: [(offset: Int, element: String)]) {
        frozen = lines
        frozenAt = session.terminalReceived
    }

    /// Firmware wants capitals ("m115" becomes "M115"), except in the text of messages and file names.
    static func prepared(_ line: String) -> String {
        let posix = Locale(identifier: "en_US_POSIX")
        let parts = line.split(separator: " ", maxSplits: 1)
        let word = parts.first.map { $0.uppercased(with: posix) } ?? ""
        let textCommands: Set<String> = ["M117", "M118", "M23", "M28", "M30", "M32"]
        if parts.count > 1, textCommands.contains(word) { return word + " " + parts[1] }
        return line.uppercased(with: posix)
    }

    private func send(_ saved: PrinterJournal.SavedCommand) {
        let lines = saved.gcode.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        session.sendGcode(lines.map(Self.prepared).joined(separator: "\n"))
        sentHere = Array((sentHere + lines.map(Self.normalised)).suffix(50))
        frozen = nil
    }

    private func send() {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        session.sendGcode(Self.prepared(trimmed))
        if history.last != trimmed { history.append(trimmed) }
        sentHere = Array((sentHere + [Self.normalised(trimmed)]).suffix(50))
        historyIndex = nil
        command = ""
        // Show the reply.
        frozen = nil
    }

    private func recall(_ delta: Int) -> KeyPress.Result {
        guard !history.isEmpty else { return .ignored }
        let index = max(0, min(history.count, (historyIndex ?? history.count) + delta))
        historyIndex = index
        command = index < history.count ? history[index] : ""
        return .handled
    }
}

/// Adds or changes a saved command: a name for its button, and the G-code it sends.
struct SavedCommandSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PrinterJournal.SavedCommand
    let isNew: Bool
    let save: (PrinterJournal.SavedCommand) -> Void
    let remove: () -> Void

    init(command: PrinterJournal.SavedCommand, isNew: Bool, save: @escaping (PrinterJournal.SavedCommand) -> Void, remove: @escaping () -> Void) {
        _draft = State(initialValue: command)
        self.isNew = isNew
        self.save = save
        self.remove = remove
    }

    private var trimmed: PrinterJournal.SavedCommand {
        var copy = draft
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.gcode = copy.gcode.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isNew ? "Save a command" : "Change a saved command").font(Typeface.title).foregroundStyle(Palette.paper)
                Text("It becomes a button on the Console tab for this printer. Put each command on its own line to send several in a row.")
                    .font(Typeface.body).foregroundStyle(Palette.dust)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Button name").font(Typeface.caption).foregroundStyle(Palette.faint)
                TextField("For example, Show settings", text: $draft.name)
                    .plateField()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("G-code").font(Typeface.caption).foregroundStyle(Palette.faint)
                TextEditor(text: $draft.gcode)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Palette.paper)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .padding(8)
                    .frame(height: 120)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.graphite))
            }
            HStack {
                if !isNew {
                    Button("Remove", role: .destructive) {
                        remove()
                        dismiss()
                    }
                    .buttonStyle(.plateQuiet)
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plateQuiet).keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(trimmed)
                    dismiss()
                }
                .buttonStyle(.plate)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed.name.isEmpty || trimmed.gcode.isEmpty)
            }
        }
        .padding(26)
        .frame(width: 460)
        .background(Palette.extrusion)
    }
}

struct ConsoleLine: View {
    let line: String
    var highlight: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(direction).foregroundStyle(highlight ?? directionColor).frame(width: 14)
            Text(content).foregroundStyle(contentColor)
        }
        .font(.system(size: 12.5, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        // The tint spills slightly past the line, so highlighting never changes a line's size.
        .background {
            if let highlight {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(highlight.opacity(0.16))
                    .padding(.horizontal, -6)
                    .padding(.vertical, -1.5)
            }
        }
    }

    private var isSend: Bool { line.hasPrefix("Send:") }
    private var isRecv: Bool { line.hasPrefix("Recv:") }
    private var isError: Bool { line.localizedCaseInsensitiveContains("error") || line.contains("!!") }

    private var direction: String { isSend ? "→" : isRecv ? "←" : "•" }
    private var directionColor: Color { isError ? Palette.hot : isSend ? Palette.accent : isRecv ? Palette.cold : Palette.faint }
    private var content: String {
        if isSend || isRecv { return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        return line
    }
    private var contentColor: Color { isError ? Palette.hot : isSend ? Palette.dust : isRecv ? Palette.paper : Palette.faint }
}


struct TerminalFilter: Identifiable {
    let name: String
    let regex: NSRegularExpression
    var id: String { name }

    /// "Suppress temperature messages" reads as "Temperature messages" under a "Hide" heading. OctoPrint's standard
    /// filters are named in the app's language; filters you added in OctoPrint keep your own names.
    var label: String {
        switch name {
        case "Suppress temperature messages": return String(localized: "Temperature messages")
        case "Suppress SD status messages": return String(localized: "SD status messages")
        case "Suppress position messages": return String(localized: "Position messages")
        case "Suppress wait responses": return String(localized: "Wait responses")
        case "Suppress processing responses": return String(localized: "Processing responses")
        case "Suppress MMU chatter": return String(localized: "MMU chatter")
        default:
            let trimmed = name.hasPrefix("Suppress ") ? String(name.dropFirst("Suppress ".count)) : name
            return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        }
    }

    func matches(_ line: String) -> Bool {
        regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    init?(name: String, pattern: String) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        self.name = name
        self.regex = regex
    }

    /// The filters configured in OctoPrint (`terminalFilters`), or OctoPrint's standard set if none are known yet.
    static func fromSettings(_ settings: JSONValue?) -> [TerminalFilter] {
        let configured = (settings?["terminalFilters"]?.arrayValue ?? []).compactMap { entry -> TerminalFilter? in
            guard let name = entry["name"]?.stringValue, let regex = entry["regex"]?.stringValue else { return nil }
            return cache(name: name, pattern: regex)
        }
        return configured.isEmpty ? standard : configured
    }

    static let standard: [TerminalFilter] = [
        ("Suppress temperature messages", #"(Send: (N\d+\s+)?M105)|(Recv:\s+(ok\s+([PBN]\d+\s+)*)?([BCLPR]|T\d*):-?\d+)"#),
        ("Suppress SD status messages", #"(Send: (N\d+\s+)?M27)|(Recv: SD printing byte)|(Recv: Not SD printing)"#),
        ("Suppress position messages", #"(Send:\s+(N\d+\s+)?M114)|(Recv:\s+(ok\s+)?X:[+-]?([0-9]*[.])?[0-9]+\s+Y:[+-]?([0-9]*[.])?[0-9]+\s+Z:[+-]?([0-9]*[.])?[0-9]+\s+E\d*:[+-]?([0-9]*[.])?[0-9]+).*"#),
        ("Suppress wait responses", #"Recv: wait"#),
        ("Suppress processing responses", #"Recv: (echo:\s*)?busy:\s*processing"#),
    ].compactMap { TerminalFilter(name: $0.0, pattern: $0.1) }

    /// OctoMac's own extra: the Prusa MMU's constant status chatter.
    static let mmu = TerminalFilter(name: "Suppress MMU chatter", pattern: #"Recv: echo:MMU2?:"#)!

    @MainActor private static var compiled: [String: TerminalFilter] = [:]

    private static func cache(name: String, pattern: String) -> TerminalFilter? {
        MainActor.assumeIsolated {
            let key = name + "\u{0}" + pattern
            if let hit = compiled[key] { return hit }
            let filter = TerminalFilter(name: name, pattern: pattern)
            compiled[key] = filter
            return filter
        }
    }
}

/// The switches behind the Console's "Hide messages" button.
struct TerminalFilterList: View {
    let filters: [TerminalFilter]
    let enabled: Set<String>
    let toggle: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hide these messages").font(Typeface.caption).foregroundStyle(Palette.faint)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            ForEach(filters) { filter in
                Toggle(isOn: Binding(get: { enabled.contains(filter.name) }, set: { toggle(filter.name, $0) })) {
                    Text(filter.label).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Palette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .padding(10)
        .frame(width: 290)
        .background(Palette.extrusion)
        .presentationBackground(Palette.extrusion)
    }
}

/// Words and phrases to pick out in the console, each with its own colour.
struct ConsoleHighlightEditor: View {
    let terms: [String]
    @Binding var replies: Bool
    let save: ([String]) -> Void
    @State private var draft = ""

    static let colors: [Color] = [Palette.warm, Palette.cold, Color(hex: 0xC792EA), Palette.hot, Color(hex: 0xF29E4C)]
    static func color(at index: Int) -> Color { colors[index % colors.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $replies) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Replies to my commands").font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                    Text("Tints what you send from here and the printer's answer.").font(Typeface.caption).foregroundStyle(Palette.faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Palette.accent)

            Divider().overlay(Palette.edge)

            Text("Highlight lines containing").font(Typeface.caption).foregroundStyle(Palette.faint)
            HStack(spacing: 8) {
                TextField("A word or phrase, e.g. FR:", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Palette.paper)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.graphite))
                    .onSubmit(add)
                    .overlay(alignment: .trailing) { ClearFieldButton(text: $draft).padding(.trailing, 8) }
                Button("Add", action: add)
                    .buttonStyle(.plate)
                    .controlSize(.small)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(Array(terms.enumerated()), id: \.element) { index, term in
                HStack(spacing: 8) {
                    Circle().fill(Self.color(at: index)).frame(width: 9, height: 9)
                    Text(term).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.paper).lineLimit(1)
                    Spacer()
                    Button { save(terms.filter { $0 != term }) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.faint)
                        .help("Stop highlighting \(term)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Self.color(at: index).opacity(0.12)))
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Palette.extrusion)
        .presentationBackground(Palette.extrusion)
    }

    private func add() {
        let term = draft.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !terms.contains(term) else { draft = ""; return }
        save(terms + [term])
        draft = ""
    }
}
