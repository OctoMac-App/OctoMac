import AppKit
import SwiftUI
import Foundation
import Observation
import OctoPrintKit

struct TemperaturePoint: Identifiable, Hashable {
    var time: Date
    var heater: String
    var actual: Double?
    var target: Double?

    var id: String { "\(heater)@\(time.timeIntervalSince1970)" }
}

/// Something worth marking on the temperature chart (print started, cancelled, printer disconnected, …).
struct ChartEvent: Identifiable, Hashable {
    enum Kind: Hashable {
        case started, done, cancelled, failed, paused, resumed, connected, disconnected, error

        init?(eventType: String) {
            switch eventType {
            case "PrintStarted": self = .started
            case "PrintDone": self = .done
            case "PrintCancelled": self = .cancelled
            case "PrintFailed": self = .failed
            case "PrintPaused": self = .paused
            case "PrintResumed": self = .resumed
            case "Connected": self = .connected
            case "Disconnected": self = .disconnected
            case "Error": self = .error
            default: return nil
            }
        }

        var label: String {
            switch self {
            case .started: "Start"
            case .done: "Done"
            case .cancelled: "Cancel"
            case .failed: "Failed"
            case .paused: "Pause"
            case .resumed: "Resume"
            case .connected: "Connected"
            case .disconnected: "Disconnected"
            case .error: "Error"
            }
        }
    }

    let id = UUID()
    let time: Date
    let kind: Kind
}

/// A file being uploaded to the printer, for the upload panel.
struct UploadItem: Identifiable, Equatable {
    enum State: Equatable { case uploading, done, failed(String) }
    let id = UUID()
    let filename: String
    let size: Int?
    var fraction: Double = 0
    var state: State = .uploading
}

struct ErrorBanner: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

/// Live state for one OctoPrint instance: REST client + push socket + everything the UI shows.
@MainActor
@Observable
final class PrinterSession {
    enum Link: Equatable {
        case needsAPIKey
        case connecting
        case online
        case offline(String?)
    }

    let instance: Instance
    let client: OctoPrintClient
    private let push: PushClient
    private var pushTask: Task<Void, Never>?

    // Link / server
    private(set) var link: Link
    private(set) var user: String?
    private(set) var version: VersionInfo?

    // Printer
    private(set) var state: PrinterState?
    private(set) var job: JobInfo?
    private(set) var progress: JobProgress?
    private(set) var currentZ: Double?
    private(set) var heaters: [String: TemperatureData] = [:]
    private(set) var temperatureHistory: [TemperaturePoint] = []
    /// Print and connection events seen while the app has been running, for the temperature chart.
    private(set) var chartEvents: [ChartEvent] = []
    private(set) var terminal: [String] = []
    /// Every console line received, including ones since trimmed from `terminal`; counts new lines while the console is paused.
    private(set) var terminalReceived = 0
    private(set) var connection: ConnectionInfo?
    private(set) var profiles: [PrinterProfile] = []

    // Files & system
    private(set) var files: [FileEntry] = []
    private(set) var freeSpace: Int?
    private(set) var systemCommands: [SystemCommand] = []
    private(set) var settings: JSONValue?

    var error: ErrorBanner?

    // Prusa MMU plugin
    /// Set while the plugin is waiting for a filament choice; the date is when it asked.
    private(set) var mmuPromptSince: Date?
    /// The slot the MMU has loaded, if known.
    private(set) var mmuTool: Int?
    private(set) var mmuPrusaVersion: String?
    /// Demo sessions have no server to talk to.
    private var isDemoSession = false
    /// Uploads in progress (and briefly after they finish), shown in the upload panel.
    private(set) var uploads: [UploadItem] = []

    // Plugins and health
    /// Real layer numbers from the DisplayLayerProgress plugin.
    private(set) var layerProgress: LayerProgress?
    /// Set while Bed Level Visualizer is measuring the bed.
    private(set) var bedMeasuringSince: Date?
    /// A mesh measured while the app has been running (newer than the one stored in the plugin's settings).
    private(set) var measuredMesh: BedLevelVisualizer.Mesh?
    private(set) var systemInfo: [String: JSONValue] = [:]
    private(set) var pi: PiSupportInfo?
    private(set) var throttle: ThrottleState?
    private(set) var printerError: PrinterErrorInfo?
    private(set) var updates: [SoftwareComponent]?
    private(set) var logs: [LogFile] = []
    private(set) var timelapses: TimelapseList?
    private(set) var customControls: [CustomControl] = []
    /// Print speed and flow, as last set here or reported by the printer (M220 / M221).
    var feedRate = 100.0
    var flowRate = 100.0
    /// For notifications: a pause asked for from this app needs no banner, and a disconnect only matters mid-print.
    private var pausedHere = false
    private var wasPrinting = false

    /// The printer's camera stream. Owned here (not by a view) so it stays connected while other printers are shown.
    let camera = MJPEGStreamer()

    static let temperatureWindow: TimeInterval = 30 * 60
    static let terminalLimit = 2000

    init(instance: Instance, apiKey: String?) {
        self.instance = instance
        client = OctoPrintClient(baseURL: instance.baseURL, apiKey: apiKey)
        push = PushClient(client: client, throttle: instance.pushThrottle)
        link = (apiKey?.isEmpty ?? true) ? .needsAPIKey : .connecting
    }

    // MARK: Derived

    var flags: PrinterStateFlags { state?.flags ?? PrinterStateFlags() }

    /// Whether OctoPrint has a working serial link to the printer. Taken from the live push state when we have it;
    /// the connection endpoint is only refreshed on events, so it's the fallback.
    var isPrinterConnected: Bool {
        if let state { return state.flags.operational }
        return connection?.isConnected ?? false
    }

    /// OctoPrint is opening the serial port / handshaking ("Connecting", "Detecting serial connection", …).
    var isPrinterConnecting: Bool {
        guard let state else { return false }
        return !state.flags.operational && !state.flags.closedOrError
    }

    /// The serial link dropped because of an error (as opposed to simply never being connected).
    var printerFault: Bool {
        flags.error || state?.text.localizedCaseInsensitiveContains("error") == true
    }

    /// Ready for manual control or starting a print: connected and not running a job.
    var canControl: Bool { link == .online && isPrinterConnected && !flags.isJobActive }

    var stateText: String {
        switch link {
        case .needsAPIKey: "Needs API key"
        case .connecting: "Connecting…"
        case .offline(let reason): reason.map { "Offline – \($0)" } ?? "Offline"
        case .online:
            if isPrinterConnecting { "Connecting to printer…" }
            else if !isPrinterConnected { printerFault ? "Printer stopped answering" : "Printer not connected" }
            else { state?.text ?? "Online" }
        }
    }

    /// Plain-language reason an action can't run right now, or nil if it can.
    var controlBlocker: String? {
        if link != .online { return "OctoMac isn't connected to this OctoPrint server." }
        if isPrinterConnecting { return "OctoPrint is still connecting to the printer." }
        if !isPrinterConnected { return "The printer isn't connected. Connect it, then try again." }
        if flags.isJobActive { return "The printer is busy with a print. Wait for it to finish, or stop it first." }
        return nil
    }

    /// Every camera OctoPrint knows about (several on OctoPrint 1.9 and later).
    var webcams: [Webcam] { Webcam.list(from: settings) }

    /// The camera being shown: the one you picked for this printer, or OctoPrint's default.
    var webcam: Webcam? {
        let cams = webcams
        let picked = UserDefaults.standard.string(forKey: "camera.\(instance.id.uuidString)")
        let preferred = settings?.value(at: "webcam", "defaultWebcam")?.stringValue
        return cams.first { $0.name == picked } ?? cams.first { $0.name == preferred } ?? cams.first
    }

    func chooseWebcam(_ cam: Webcam) {
        UserDefaults.standard.set(cam.name, forKey: "camera.\(instance.id.uuidString)")
        selectedWebcamName = cam.name
        if !isDemoSession, let url = webcamStreamURL { camera.start(url: url, apiKey: client.apiKey) }
    }

    /// Changes when a camera is picked, so views showing the camera update.
    private(set) var selectedWebcamName: String?

    var webcamStreamURL: URL? {
        _ = selectedWebcamName
        return webcam.flatMap { client.resolve($0.stream) }
    }

    var webcamTransform: (flipH: Bool, flipV: Bool, rotate90: Bool) {
        _ = selectedWebcamName
        return (webcam?.flipH ?? false, webcam?.flipV ?? false, webcam?.rotate90 ?? false)
    }

    /// Temperature presets from OctoPrint's settings (`temperature.profiles`).
    var temperaturePresets: [(name: String, extruder: Double, bed: Double)] {
        (settings?.value(at: "temperature", "profiles")?.arrayValue ?? []).compactMap { profile in
            guard let name = profile["name"]?.stringValue else { return nil }
            return (name, profile["extruder"]?.doubleValue ?? 0, profile["bed"]?.doubleValue ?? 0)
        }
    }

    /// Finds the file-list entry (with analysis and thumbnail) for a job's file.
    func fileEntry(for jobFile: JobFile?) -> FileEntry? {
        guard let path = jobFile?.path else { return nil }
        return fileEntry(path: path, origin: jobFile?.origin ?? "local")
    }

    func fileEntry(path: String, origin: String) -> FileEntry? {
        func search(_ entries: [FileEntry]) -> FileEntry? {
            for entry in entries {
                if entry.path == path, entry.origin.rawValue == origin { return entry }
                if let found = search(entry.children ?? []) { return found }
            }
            return nil
        }
        return search(files)
    }

    /// The Prusa MMU plugin's filament list and options, when the plugin is installed.
    var mmu: PrusaMMU.Settings? { PrusaMMU.Settings(settings: settings) }

    /// The MK3 family can't skip the prompt (the printer then asks on its own screen); later models can.
    var mmuCanSkip: Bool { mmuPrusaVersion.map { $0 != "MK3" } ?? false }

    var bedLevel: BedLevelVisualizer.Settings? { BedLevelVisualizer.Settings(settings: settings) }
    var bedMesh: BedLevelVisualizer.Mesh? { measuredMesh ?? bedLevel?.stored }
    var hasLayerPlugin: Bool { settings?.value(at: "plugins", LayerProgress.pluginID) != nil }

    /// The printer's firmware, as it introduced itself (M115).
    var firmware: String? {
        systemInfo["printer.firmware"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The reason the printer last stopped with an error, while it's still in that state.
    var faultDetail: String? {
        guard !isPrinterConnected, let printerError, !printerError.isEmpty else { return nil }
        return printerError.error
    }

    var currentProfile: PrinterProfile? {
        profiles.first { $0.id == connection?.current.printerProfile } ?? profiles.first { $0.current == true } ?? profiles.first
    }

    // MARK: Lifecycle

    func start() {
        guard pushTask == nil, link != .needsAPIKey else { return }
        let push = self.push
        pushTask = Task { [weak self] in
            await push.start()
            for await event in push.events {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    func stop() {
        // A popped-out camera for a printer that's going away (removed, or demo mode switched) closes too.
        if PictureInPicture.shared.sessionID == instance.id { PictureInPicture.shared.close() }
        camera.stop()
        pushTask?.cancel()
        pushTask = nil
        let push = self.push
        Task { await push.finish() }
    }

    func refreshAll() async {
        async let version: Void = refreshVersion()
        async let connection: Void = refreshConnection()
        async let files: Void = refreshFiles()
        async let settings: Void = refreshSettings()
        async let system: Void = refreshSystemCommands()
        async let profiles: Void = refreshProfiles()
        async let temps: Void = loadTemperatureHistory()
        async let health: Void = refreshHealth()
        async let controls: Void = refreshCustomControls()
        _ = await (version, connection, files, settings, system, profiles, temps, health, controls)
        if hasLayerPlugin { layerProgress = try? await client.layerProgress() }
    }

    /// Firmware, Raspberry Pi health and the last printer error. Quietly skipped where unsupported.
    func refreshHealth() async {
        guard !isDemoSession else { return }
        if let info = try? await client.systemInfo() { systemInfo = info }
        if let info = try? await client.piSupport() {
            pi = info
            throttle = info.throttle
        }
        printerError = try? await client.lastPrinterError()
    }

    func refreshUpdates(force: Bool = false) async {
        guard !isDemoSession else { return }
        if force {
            updates = await attempt { [client] in try await client.softwareUpdates(force: true) } ?? updates
        } else if let list = try? await client.softwareUpdates() {
            updates = list
        }
    }

    func refreshTimelapses() async {
        guard !isDemoSession else { return }
        if let list = try? await client.timelapses() { timelapses = list }
    }

    func refreshCustomControls() async {
        guard !isDemoSession else { return }
        if let list = try? await client.customControlList() { customControls = list }
    }

    func run(_ action: CustomControl.Action, values: [String: String]) {
        guard !isDemoSession else { return }
        if let script = action.script {
            perform { [client] in try await client.runScript(script, parameters: values) }
        } else {
            let commands = action.resolvedCommands(values)
            perform { [client] in try await client.sendGcode(commands) }
        }
    }

    func timelapseData(_ file: TimelapseFile) async -> Data? {
        guard !isDemoSession else { return nil }
        return await attempt { [client] in try await client.timelapseData(file) }
    }

    func deleteTimelapse(_ file: TimelapseFile) {
        perform { [client, weak self] in
            try await client.deleteTimelapse(file.name)
            await self?.refreshTimelapses()
        }
    }

    func renderTimelapse(_ file: TimelapseFile) {
        perform { [client, weak self] in
            try await client.renderTimelapse(file.name)
            await self?.refreshTimelapses()
        }
    }

    /// Every file's most recent print, newest first, from OctoPrint's per-file print history.
    var recentPrints: [FileEntry] {
        func walk(_ entries: [FileEntry]) -> [FileEntry] {
            entries.flatMap { entry in (entry.prints?.last?.date != nil ? [entry] : []) + walk(entry.children ?? []) }
        }
        return walk(files).sorted { ($0.prints?.last?.date ?? 0) > ($1.prints?.last?.date ?? 0) }
    }

    func refreshLogs() async {
        guard !isDemoSession else { return }
        if let list = try? await client.logFiles() { logs = list.files.sorted { ($0.date ?? 0) > ($1.date ?? 0) } }
    }

    func refreshVersion() async { version = await attempt { try await client.version() } ?? version }
    func refreshConnection() async { connection = await attempt { try await client.connection() } ?? connection }
    func refreshSettings() async {
        settings = await attempt { try await client.settings() } ?? settings
        if let url = webcamStreamURL {
            camera.start(url: url, apiKey: client.apiKey)
        } else {
            camera.stop()
        }
    }
    func refreshProfiles() async {
        profiles = await attempt { try await client.printerProfiles() } ?? profiles
        // Drop duplicate tool readings we may already have taken in before the profile arrived.
        heaters = heaters.filter { !isDuplicateTool($0.key) }
        temperatureHistory.removeAll { isDuplicateTool($0.heater) }
    }

    /// Printers whose extruders share one nozzle (e.g. a Prusa MMU, set up as 5 extruders) report the same
    /// hotend once per extruder. Only the first is real.
    private func isDuplicateTool(_ key: String) -> Bool {
        guard currentProfile?.extruder?.sharedNozzle == true, case .tool(let index) = HeaterKind(key: key) else { return false }
        return index > 0
    }

    func refreshSystemCommands() async {
        // Not every user may run system commands; don't nag about it.
        systemCommands = (try? await client.systemCommands().all) ?? systemCommands
    }

    func refreshFiles() async {
        guard let list = await attempt({ try await client.files(recursive: true) }) else { return }
        files = list.files
        freeSpace = list.free
        prefetchThumbnails()
    }

    /// Warms the thumbnail cache so this printer's files show their previews the moment it's selected.
    private func prefetchThumbnails() {
        let client = self.client
        func walk(_ entries: [FileEntry]) -> [URL] {
            entries.flatMap { entry in (entry.thumbnail.flatMap(client.resolve).map { [$0] } ?? []) + walk(entry.children ?? []) }
        }
        let urls = walk(files)
        Task {
            for url in urls where ThumbnailStore.shared.cached(url) == nil {
                _ = await ThumbnailStore.shared.image(for: url, client: client)
            }
        }
    }

    private func loadTemperatureHistory() async {
        guard let status = try? await client.printerStatus(history: true, limit: 600) else { return }
        if let state = status.state { self.state = state }
        if let temperature = status.temperature {
            heaters = temperature.current.heaters.filter { !isDuplicateTool($0.key) }
            appendTemperatures(temperature.history)
        }
    }

    // MARK: Push handling

    private func handle(_ event: PushEvent) {
        switch event {
        case .connecting:
            if link != .online { link = .connecting }
        case .connected(let user):
            link = .online
            self.user = user
            Task {
                await refreshAll()
                if mmu != nil { try? await client.refreshMMUState() }
            }
        case .disconnected(let reason):
            if link != .needsAPIKey { link = .offline(reason) }
        case .message(let message):
            handle(message)
        }
    }

    private func handle(_ message: PushMessage) {
        switch message {
        case .current(let payload):
            apply(payload)
        case .history(let payload):
            apply(payload)
            terminal = Array(payload.logs.suffix(Self.terminalLimit))
        case .event(let event):
            handle(event)
        case .plugin(let id, let data) where id == PrusaMMU.pluginID:
            handleMMU(data)
        case .plugin(let id, let data) where id == LayerProgress.pushID:
            layerProgress = LayerProgress(push: data)
        case .plugin(let id, let data) where id == PiSupportInfo.pluginID:
            if let update = PiSupportInfo.throttleUpdate(data) {
                if update.currentIssue, throttle?.currentIssue != true {
                    notify(.piWarning, "Raspberry Pi warning",
                           update.currentUndervoltage ? "The Pi isn't getting enough power. Prints may stutter; try a better power supply."
                                                      : "The Pi is too hot and is slowing down. Prints may stutter.")
                }
                throttle = update
            }
        case .plugin(let id, let data) where id == BedLevelVisualizer.pluginID:
            handleBedLevel(data)
        default:
            break
        }
    }

    private func apply(_ payload: CurrentPayload) {
        if let state = payload.state {
            self.state = state
            if state.flags.isJobActive { wasPrinting = true } else if state.flags.operational { wasPrinting = false }
            // Readings from before a disconnect are stale; don't keep showing them as current.
            if state.flags.closedOrError {
                heaters = [:]
                currentZ = nil
            }
        }
        if let job = payload.job { self.job = job }
        if let progress = payload.progress { self.progress = progress }
        if payload.state?.flags.closedOrError != true { currentZ = payload.currentZ }
        if let latest = payload.temps.last {
            heaters.merge(latest.heaters.filter { !isDuplicateTool($0.key) }) { _, new in new }
        }
        appendTemperatures(payload.temps)
        if !payload.logs.isEmpty {
            readRates(from: payload.logs)
            terminalReceived += payload.logs.count
            terminal.append(contentsOf: payload.logs)
            if terminal.count > Self.terminalLimit { terminal.removeFirst(terminal.count - Self.terminalLimit) }
        }
    }

    private func handleMMU(_ data: JSONValue) {
        switch PrusaMMU.Message(data) {
        case .showPrompt:
            mmuPromptSince = .now
            notify(.needsAttention, "Choose a filament", "The print is waiting for you to pick an MMU filament.")
        case .closePrompt:
            mmuPromptSince = nil
        case .state(let tool, let version):
            mmuTool = tool
            if let version, !version.isEmpty { mmuPrusaVersion = version }
        case nil:
            break
        }
    }

    /// Answers the MMU prompt with a slot, or `nil` to skip.
    func chooseMMUFilament(_ index: Int?) {
        mmuPromptSince = nil
        if let index { mmuTool = index }
        guard !isDemoSession else { return }
        perform { [client] in try await client.selectMMUFilament(index) }
    }

    private func handleBedLevel(_ data: JSONValue) {
        switch BedLevelVisualizer.Message(data) {
        case .processing:
            if bedMeasuringSince == nil { bedMeasuringSince = .now }
        case .mesh(var mesh):
            bedMeasuringSince = nil
            let measured = Date.now.formatted(date: .abbreviated, time: .shortened)
            mesh.measured = measured
            measuredMesh = mesh
            // Like the plugin's own page: keep the latest mesh in its settings, so it's there next time.
            if bedLevel?.saveMesh ?? true {
                perform { [client] in try await client.storeBedMesh(mesh, measured: measured) }
            }
        case .error(let message):
            bedMeasuringSince = nil
            error = ErrorBanner(message: "Bed Visualizer couldn't read the bed: \(message)")
        case nil:
            break
        }
    }

    /// Picks up the speed and flow factors from the printer's replies to M220 / M221
    /// (for example "FR:110%" and "E0 Flow: 95%").
    private func readRates(from lines: [String]) {
        for line in lines where line.hasPrefix("Recv:") {
            if let match = line.firstMatch(of: /FR:\s*(\d+)%/), let value = Double(match.1) { feedRate = value }
            if let match = line.firstMatch(of: /(?:Flow|extrude multiply):\s*(\d+)%/), let value = Double(match.1) { flowRate = value }
        }
    }

    private func notify(_ kind: NotificationKind, _ title: String, _ body: String) {
        guard !isDemoSession else { return }
        Notifier.shared.post(kind, printer: instance, title: title, body: body)
    }

    private func notifyAbout(_ event: ServerEvent) {
        let file = event.payload["name"]?.stringValue.map { SlicedName($0).title }
        switch event.type {
        case "PrintDone":
            let time = event.payload["time"]?.doubleValue.map { " after \(Fmt.duration($0))" } ?? ""
            notify(.printDone, "Print finished", "\(file ?? "The print") finished\(time).")
        case "PrintFailed":
            // A cancel from OctoMac or OctoPrint arrives as PrintCancelled; this is the printer or an error.
            let reason = event.payload["reason"]?.stringValue == "cancelled" ? "was stopped" : "failed"
            notify(.printFailed, "Print \(reason == "failed" ? "failed" : "stopped")", "\(file ?? "The print") \(reason).")
        case "FilamentChange":
            notify(.needsAttention, "Filament change", "The printer is asking for a filament change.")
        case "PrintPaused":
            if !pausedHere { notify(.needsAttention, "Print paused", "\(file ?? "The print") is paused and waiting for you.") }
            pausedHere = false
        case "Error":
            let message = event.payload["error"]?.stringValue ?? "The printer reported an error."
            notify(.printerProblem, "Printer error", message)
        case "Disconnected":
            if wasPrinting { notify(.printerProblem, "Printer disconnected", "The printer stopped answering in the middle of a print.") }
            wasPrinting = false
        default:
            break
        }
    }

    private func handle(_ event: ServerEvent) {
        notifyAbout(event)
        if let kind = ChartEvent.Kind(eventType: event.type) {
            chartEvents.append(ChartEvent(time: .now, kind: kind))
            let cutoff = Date.now.addingTimeInterval(-Self.temperatureWindow)
            chartEvents.removeAll { $0.time < cutoff }
        }
        switch event.type {
        case "PrintStarted":
            layerProgress = nil
        case "MovieDone", "MovieFailed", "MovieRendering":
            Task { await refreshTimelapses() }
        case "UpdatedFiles", "FileAdded", "FileRemoved", "FolderAdded", "FolderRemoved", "MetadataAnalysisFinished", "PrintDone":
            Task { await refreshFiles() }
        case "Connected", "Disconnected", "Connecting", "PrinterProfileModified", "Error":
            Task {
                await refreshConnection()
                await refreshHealth()
            }
            if event.type == "Connected" {
                feedRate = 100
                flowRate = 100
            }
        case "SettingsUpdated":
            Task { await refreshSettings() }
        default:
            break
        }
    }

    private func appendTemperatures(_ snapshots: [TemperatureSnapshot]) {
        guard !snapshots.isEmpty else { return }
        for snapshot in snapshots {
            let time = snapshot.time ?? .now
            if let last = temperatureHistory.last?.time, time <= last { continue }
            for (heater, data) in snapshot.heaters where !isDuplicateTool(heater) {
                temperatureHistory.append(TemperaturePoint(time: time, heater: heater, actual: data.actual, target: data.target))
            }
        }
        let cutoff = Date.now.addingTimeInterval(-Self.temperatureWindow)
        if let first = temperatureHistory.first, first.time < cutoff {
            temperatureHistory.removeAll { $0.time < cutoff }
        }
    }

    // MARK: Actions

    /// Runs an API call, surfacing failures as a banner. Returns nil on failure.
    @discardableResult
    func attempt<T>(_ operation: () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch is CancellationError {
            return nil
        } catch OctoPrintError.conflict(let message) {
            // OctoPrint's 409 messages are generic (e.g. "already printing" when the printer is simply disconnected),
            // so prefer what we know about the printer's state.
            self.error = ErrorBanner(message: controlBlocker ?? message ?? "The printer can't do that right now.")
            return nil
        } catch OctoPrintError.unauthorized(let message) {
            // 403 means either a bad key or a permission the account lacks; only the first should lock the printer.
            let user = try? await client.currentUser()
            if user?.name == nil {
                link = .needsAPIKey
                self.error = ErrorBanner(message: "OctoPrint no longer accepts this API key. Request access again.")
            } else {
                self.error = ErrorBanner(message: message ?? "Your OctoPrint account doesn't have permission to do that.")
            }
            return nil
        } catch {
            self.error = ErrorBanner(message: error.localizedDescription)
            return nil
        }
    }

    func perform(_ operation: @escaping () async throws -> Void) {
        Task { await attempt(operation) }
    }

    func jobCommand(_ command: JobCommand) {
        switch command {
        case .pause, .togglePause: pausedHere = true
        default: break
        }
        perform { [client] in try await client.job(command) }
    }

    /// True while a heater is still climbing towards its target (e.g. the M109/M190 wait at the start of a print).
    var isWaitingForHeaters: Bool {
        heaters.contains { key, data in
            guard HeaterKind(key: key).isHeater, let actual = data.actual, let target = data.target else { return false }
            return target > 0 && actual < target - 3
        }
    }

    /// Cancels the job, exactly like OctoPrint's own Cancel button.
    func stopPrint() { jobCommand(.cancel) }

    /// M112: the firmware halts immediately (heaters and motors off). The printer must be reset and reconnected
    /// afterwards. OctoPrint sends M112 straight to the printer, ahead of anything queued.
    func emergencyStop() { sendGcode("M112") }

    /// Breaks the firmware out of an M109/M190 heating wait (used while a cancel is stuck behind one).
    func interruptHeating() { sendGcode("M108") }
    func setTarget(_ value: Double, heater: String) { perform { [client] in try await client.setTarget(value, forHeater: heater) } }
    func jog(x: Double? = nil, y: Double? = nil, z: Double? = nil) { perform { [client] in try await client.jog(x: x, y: y, z: z) } }
    func home(_ axes: [OctoPrintKit.Axis]) { perform { [client] in try await client.home(axes) } }
    func extrude(_ amount: Double) { perform { [client] in try await client.extrude(amount) } }
    func setFeedRate(_ percent: Int) {
        feedRate = Double(percent)
        guard !isDemoSession else { return }
        perform { [client] in try await client.setFeedRate(percent) }
    }

    func setFlowRate(_ percent: Int) {
        flowRate = Double(percent)
        guard !isDemoSession else { return }
        perform { [client] in try await client.setFlowRate(percent) }
    }

    /// Measures the bed with Bed Level Visualizer's G-code.
    func measureBed() {
        // Only with the plugin installed and G-code that probes the bed.
        guard let bedLevel, bedLevel.canMeasure else { return }
        let commands = bedLevel.commandLines
        if let blocker = controlBlocker {
            error = ErrorBanner(message: blocker)
            return
        }
        bedMeasuringSince = .now
        guard !isDemoSession else { return }
        perform { [client] in try await client.measureBed(commands: commands) }
    }

    func cancelBedMeasurement() {
        bedMeasuringSince = nil
        guard !isDemoSession else { return }
        perform { [client] in try await client.cancelBedMeasurement() }
    }

    func setBedMeasureCommand(_ command: String) {
        guard !isDemoSession else { return }
        perform { [client, weak self] in
            try await client.setBedMeasureCommand(command)
            await self?.refreshSettings()
        }
    }

    func logContents(_ file: LogFile) async -> Data? {
        if isDemoSession { return Data(Self.demoLog.utf8) }
        return await attempt { [client] in try await client.logContents(file) }
    }
    func sendGcode(_ command: String) { perform { [client] in try await client.sendGcode(command) } }

    func setFan(percent: Double) {
        let pwm = Int((max(0, min(100, percent)) / 100 * 255).rounded())
        sendGcode(pwm == 0 ? "M107" : "M106 S\(pwm)")
    }

    func applyPreset(extruder: Double, bed: Double) {
        let toolKeys = heaters.keys.filter { $0.hasPrefix("tool") }
        perform { [client] in
            try await client.setToolTargets(Dictionary(uniqueKeysWithValues: (toolKeys.isEmpty ? ["tool0"] : toolKeys).map { ($0, extruder) }))
            try await client.setBedTarget(bed)
        }
    }

    func coolDown() { applyPreset(extruder: 0, bed: 0) }

    func connectPrinter(_ request: ConnectRequest = .init()) {
        perform { [client] in try await client.connect(request) }
    }

    func disconnectPrinter() { perform { [client] in try await client.disconnect() } }

    func select(_ file: FileEntry, print: Bool) {
        if let blocker = controlBlocker {
            error = ErrorBanner(message: blocker)
            return
        }
        perform { [client] in try await client.select(file.path, origin: file.origin, print: print) }
    }

    func delete(_ file: FileEntry) {
        perform { [client, weak self] in
            try await client.deleteFile(file.path, origin: file.origin)
            await self?.refreshFiles()
        }
    }

    func upload(_ urls: [URL], folder: String? = nil, print: Bool = false) {
        let items = urls.map { url in
            UploadItem(filename: url.lastPathComponent,
                       size: (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize)
        }
        uploads.append(contentsOf: items)
        let client = self.client
        let handlers = items.map { uploadProgressHandler($0.id) }
        Task { [weak self] in
            for ((url, item), onProgress) in zip(zip(urls, items), handlers) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    try await client.upload(fileURL: url, folder: folder, select: print, print: print && urls.count == 1,
                                            progress: onProgress)
                    self?.updateUpload(item.id) { $0.fraction = 1; $0.state = .done }
                } catch {
                    self?.updateUpload(item.id) { $0.state = .failed(error.localizedDescription) }
                }
            }
            await self?.refreshFiles()
            // Leave finished uploads on screen briefly so the result is seen; failures stay until dismissed.
            try? await Task.sleep(for: .seconds(2.5))
            self?.uploads.removeAll { item in items.contains { $0.id == item.id } && item.state == .done }
        }
    }

    private func uploadProgressHandler(_ id: UUID) -> @Sendable (Double) -> Void {
        { [weak self] fraction in
            Task { @MainActor in self?.updateUpload(id) { $0.fraction = fraction } }
        }
    }

    private func updateUpload(_ id: UUID, _ change: (inout UploadItem) -> Void) {
        guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
        change(&uploads[index])
    }

    func dismissUpload(_ id: UUID) {
        uploads.removeAll { $0.id == id }
    }

    /// Moves a file or folder into `folder` ("" for the top level).
    func move(_ file: FileEntry, toFolder folder: String) {
        let currentParent = file.path.split(separator: "/").dropLast().joined(separator: "/")
        guard currentParent != folder else { return }
        // A folder can't go inside itself.
        guard !(file.isFolder && (folder == file.path || folder.hasPrefix(file.path + "/"))) else { return }
        perform { [client, weak self] in
            try await client.move(file.path, to: folder, origin: file.origin)
            await self?.refreshFiles()
        }
    }

    func createFolder(_ name: String, in parent: String?) {
        perform { [client, weak self] in
            try await client.createFolder(name, in: parent)
            await self?.refreshFiles()
        }
    }

    func run(_ command: SystemCommand) { perform { [client] in try await client.execute(command) } }
}

// MARK: - Demo data (`--demo`)

extension PrinterSession {
    enum DemoScenario { case printing, ready, toolchanger, locked }

    func loadDemo(_ scenario: DemoScenario) {
        guard scenario != .locked else { return }
        link = .online
        user = "maker"
        version = try? (["api": "0.1", "server": "1.10.3", "text": "OctoPrint 1.10.3"] as JSONValue).decode(VersionInfo.self)

        let printing = scenario == .printing
        let toolCount = scenario == .toolchanger ? 4 : 1
        let current: JSONValue = [
            "state": [
                "text": printing ? "Printing" : "Operational",
                "flags": ["operational": true, "printing": .bool(printing), "ready": .bool(!printing), "paused": false],
            ],
            "job": [
                "file": [
                    "name": printing ? "gridfinity_bins_3x2_PLA.gcode" : "spool_holder_v4_PETG.gcode",
                    "display": printing ? "gridfinity_bins_3x2_PLA.gcode" : "spool_holder_v4_PETG.gcode",
                    "path": printing ? "workshop/gridfinity_bins_3x2_PLA.gcode" : "spool_holder_v4_PETG.gcode",
                    "origin": "local",
                ],
                "estimatedPrintTime": printing ? 12480 : 7320,
                "filament": ["tool0": ["length": printing ? 18342.5 : 9120.0, "volume": 44.1]],
            ],
            "progress": printing
                ? ["completion": 63.4, "printTime": 8040, "printTimeLeft": 4710, "printTimeLeftOrigin": "estimate"]
                : ["completion": nil, "printTime": nil, "printTimeLeft": nil],
            "currentZ": printing ? 18.4 : nil,
            "logs": .array(Self.demoTerminal.map(JSONValue.string)),
        ]
        if let payload = try? current.decode(CurrentPayload.self) { apply(payload) }
        if printing { startDemoProgress() }

        // 30 minutes of history: heat-up then hold (printing) or ambient (ready).
        let now = Date.now
        var snapshots: [TemperatureSnapshot] = []
        for step in stride(from: 1800, through: 0, by: -10) {
            let t = Double(1800 - step)
            let tool: TemperatureData
            let bed: TemperatureData
            if printing {
                let heat = min(1, t / 240)
                tool = TemperatureData(actual: 24 + (190.6 * heat) + sin(t / 13) * 0.6, target: 215)
                bed = TemperatureData(actual: 23 + (37.1 * min(1, t / 420)) + sin(t / 29) * 0.2, target: 60)
            } else {
                tool = TemperatureData(actual: 24.2 + sin(t / 90) * 0.3, target: 0)
                bed = TemperatureData(actual: 23.1 + sin(t / 120) * 0.2, target: 0)
            }
            var readings = ["tool0": tool, "bed": bed]
            // Tool-changer demo: four independent hotends, two of them heating.
            for index in 1..<toolCount {
                let target: Double = index == 1 ? 240 : 0
                let actual = target > 0 ? 24 + 214 * min(1, t / 300) + sin(t / 17) * 0.5 : 24.5 + Double(index) * 0.4 + sin(t / 70) * 0.3
                readings["tool\(index)"] = TemperatureData(actual: actual, target: target)
            }
            if toolCount > 1 {
                readings["tool0"] = TemperatureData(actual: 24 + 186 * min(1, t / 280) + sin(t / 13) * 0.6, target: 210)
                readings["bed"] = TemperatureData(actual: 23 + 47 * min(1, t / 500), target: 70)
                readings["chamber"] = TemperatureData(actual: 23 + 17 * min(1, t / 900), target: 40)
            }
            snapshots.append(TemperatureSnapshot(time: now.addingTimeInterval(-Double(step)), heaters: readings))
        }
        temperatureHistory = []
        appendTemperatures(snapshots)
        chartEvents = printing
            ? [ChartEvent(time: now.addingTimeInterval(-1790), kind: .connected), ChartEvent(time: now.addingTimeInterval(-1500), kind: .started)]
            : [ChartEvent(time: now.addingTimeInterval(-1200), kind: .done)]
        heaters = snapshots.last?.heaters ?? [:]

        let filesJSON: JSONValue = [
            "free": 21_474_836_480,
            "files": [
                ["name": "workshop", "path": "workshop", "type": "folder", "origin": "local", "children": [
                    Self.demoFile("gridfinity_bins_3x2_PLA.gcode", folder: "workshop", time: 12480, length: 18342, size: 4_812_331, daysAgo: 0, success: nil),
                    Self.demoFile("pegboard_hooks_x8.gcode", folder: "workshop", time: 3920, length: 5120, size: 1_204_112, daysAgo: 3, success: true),
                    Self.demoFile("drill_bit_index.gcode", folder: "workshop", time: 9210, length: 13870, size: 3_918_002, daysAgo: 9, success: false),
                ]],
                ["name": "calibration", "path": "calibration", "type": "folder", "origin": "local", "children": [
                    Self.demoFile("first_layer_test.gcode", folder: "calibration", time: 540, length: 610, size: 98_201, daysAgo: 21, success: true),
                    Self.demoFile("temp_tower_PETG.gcode", folder: "calibration", time: 4420, length: 4210, size: 1_820_004, daysAgo: 30, success: true),
                ]],
                Self.demoFile("spool_holder_v4_PETG.gcode", folder: nil, time: 7320, length: 9120, size: 2_731_550, daysAgo: 1, success: true),
                Self.demoFile("cable_chain_link.gcode", folder: nil, time: 1260, length: 1480, size: 402_330, daysAgo: 2, success: true),
                Self.demoFile("3dbenchy.gcode", folder: nil, time: 5100, length: 5040, size: 2_002_118, daysAgo: 45, success: true),
                Self.demoFile("lamp_shade_voronoi.stl", folder: nil, time: nil, length: nil, size: 9_201_552, daysAgo: 5, success: nil, model: true),
            ],
        ]
        if let list = try? filesJSON.decode(FileList.self) {
            files = list.files
            freeSpace = list.free
        }

        let connectionJSON: JSONValue = [
            "current": ["state": printing ? "Printing" : "Operational", "port": "/dev/ttyACM0", "baudrate": 115200, "printerProfile": "_default"],
            "options": [
                "ports": ["/dev/ttyACM0", "/dev/ttyUSB0"], "baudrates": [250000, 230400, 115200, 57600],
                "printerProfiles": [["id": "_default", "name": printing ? "Prusa MK3S+ (MMU3)" : "Ender 3 V3"]],
                "portPreference": "/dev/ttyACM0", "baudratePreference": 115200, "printerProfilePreference": "_default", "autoconnect": true,
            ],
        ]
        connection = try? connectionJSON.decode(ConnectionInfo.self)

        let profileJSON: JSONValue = [
            "id": "_default",
            "name": .string(toolCount > 1 ? "Prusa XL 4-tool" : printing ? "Prusa MK3S+ (MMU3)" : "Ender 3 V3"),
            "model": .string(toolCount > 1 ? "Original Prusa XL" : printing ? "Original Prusa MK3S+" : "Creality Ender 3 V3"),
            "heatedBed": true, "heatedChamber": .bool(toolCount > 1),
            "volume": ["width": printing ? 250 : 220, "depth": 210, "height": printing ? 220 : 250, "formFactor": "rectangular", "origin": "lowerleft"],
            "extruder": ["count": JSONValue(toolCount), "nozzleDiameter": 0.4, "sharedNozzle": false],
        ]
        profiles = (try? profileJSON.decode(PrinterProfile.self)).map { [$0] } ?? []

        let systemJSON: JSONValue = [
            "core": [
                ["action": "restart", "name": "Restart OctoPrint", "source": "core", "confirm": "You are about to restart the OctoPrint server."],
                ["action": "reboot", "name": "Reboot system", "source": "core", "confirm": "You are about to reboot the Raspberry Pi."],
                ["action": "shutdown", "name": "Shut down system", "source": "core", "confirm": "You are about to shut down the Raspberry Pi."],
            ],
            "custom": [],
        ]
        systemCommands = (try? systemJSON.decode(SystemCommandList.self))?.all ?? []

        isDemoSession = true
        if printing {
            mmuTool = 1
            mmuPrusaVersion = "MK3"
            if CommandLine.arguments.contains("--demo-mmu") { mmuPromptSince = .now }
        }
        camera.showStill(Self.demoCameraFrame(title: instance.name))
        loadDemoHealth(printing: printing, toolchanger: toolCount > 1)
        settings = [
            "webcam": ["streamUrl": "/webcam/?action=stream"],
            "plugins": .object((printing ? ["prusammu": [
                "filament": [
                    ["color": "#808080", "enabled": true, "id": 1, "name": "Urban Grey PETG"],
                    ["color": "#FFD60A", "enabled": true, "id": 2, "name": "Mango Yellow PETG"],
                    ["color": "#AEC89F", "enabled": true, "id": 3, "name": "Pistachio PETG"],
                    ["color": "#1C1C1C", "enabled": true, "id": 4, "name": "Jet Black PETG"],
                    ["color": "#008080", "enabled": true, "id": 5, "name": "Ocean Blue PETG"],
                ],
                "filamentCount": 5, "timeout": 30, "indexAtZero": false, "enablePrompt": true,
            ]] : [:]).merging([
                "DisplayLayerProgress": ["showOnState": true],
                "bedlevelvisualizer": Self.demoBedLevel(rows: printing ? 7 : 5, tilt: printing ? 0.06 : 0.14),
            ]) { a, _ in a }),
            "temperature": ["profiles": [
            ["name": "PLA", "extruder": 215, "bed": 60],
            ["name": "PETG", "extruder": 240, "bed": 85],
            ["name": "ABS", "extruder": 255, "bed": 100],
        ]],
        ]
    }

    private func loadDemoHealth(printing: Bool, toolchanger: Bool) {
        if printing { layerProgress = LayerProgress(currentLayer: 92, totalLayers: 146, averageLayerDuration: 58, lastLayerDuration: 61) }
        systemInfo = ["printer.firmware": .string(toolchanger ? "Prusa-Firmware-Buddy 6.1.3" : printing ? "Prusa-Firmware 3.14.1+8237 based on Marlin" : "Marlin 2.1.2.4")]
        pi = PiSupportInfo([
            "model": .string(printing ? "Raspberry Pi 4 Model B Rev 1.2" : "Raspberry Pi 3 Model B Plus Rev 1.3"),
            "octopi_version": "1.0.0",
            "throttle_state": ["current_issue": false, "past_issue": .bool(!printing), "past_undervoltage": .bool(!printing),
                               "current_undervoltage": false, "current_overheat": false, "past_overheat": false],
        ])
        throttle = pi?.throttle
        timelapses = try? ([
            "config": ["type": .string(printing ? "zchange" : "off")],
            "files": printing ? [
                ["name": "pegboard_hooks_x8_20260625.mp4", "size": "18.2MB", "bytes": 19_084_112, "date": "2026-06-25 16:40"],
                ["name": "drill_bit_index_20260619.mp4", "size": "41.7MB", "bytes": 43_725_005, "date": "2026-06-19 11:02"],
            ] : [],
            "unrendered": printing ? [["name": "first_layer_test", "size": "2.1MB", "bytes": 2_201_331, "date": "2026-06-07 09:15"]] : [],
        ] as JSONValue).decode(TimelapseList.self)
        if printing {
            customControls = CustomControl.parse(["controls": [
                ["name": "Filament", "children": [
                    ["name": "Load filament", "command": "M701"],
                    ["name": "Unload filament", "command": "M702", "confirm": "Is the hotend hot enough to unload?"],
                ]],
                ["name": "Maintenance", "children": [
                    ["name": "Park for nozzle change", "commands": ["G28 X Y", "G1 Z80 F600"]],
                    ["name": "Set fan speed", "command": "M106 S%(speed)s", "input": [["name": "Speed", "parameter": "speed", "default": 255]]],
                    ["name": "Wipe nozzle", "script": "wipe_nozzle"],
                ]],
            ]])
        }
        updates = [
            SoftwareComponent(id: "octoprint", name: "OctoPrint", installed: "1.10.3", available: printing ? "1.10.3" : "1.11.0",
                              updateAvailable: !printing, updatePossible: true),
            SoftwareComponent(id: "bedlevelvisualizer", name: "Bed Visualizer", installed: "1.1.2", available: "1.1.2", updateAvailable: false, updatePossible: true),
            SoftwareComponent(id: "DisplayLayerProgress", name: "DisplayLayerProgress Plugin", installed: "1.28.0", available: "1.28.0", updateAvailable: false, updatePossible: true),
            SoftwareComponent(id: "prusaslicerthumbnails", name: "Slicer Thumbnails", installed: "1.2.4", available: "1.2.4", updateAvailable: false, updatePossible: true),
        ]
        let now = Date.now.timeIntervalSince1970
        logs = [("octoprint.log", 1_204_331, 60.0), ("serial.log", 0, 3600), ("plugin_pi_support.log", 4_210, 7200), ("auth.log", 584, 86400)].map {
            try? (["name": .string($0.0), "size": JSONValue($0.1), "date": .number(now - $0.2)] as JSONValue).decode(LogFile.self)
        }
        .compactMap { $0 }
    }

    /// A gently tilted, slightly dished bed, as Bed Level Visualizer would store it.
    private static func demoBedLevel(rows: Int, tilt: Double) -> JSONValue {
        let mesh: [JSONValue] = (0..<rows).map { row in
            .array((0..<rows).map { column in
                let x = Double(column) / Double(rows - 1) - 0.5, y = Double(row) / Double(rows - 1) - 0.5
                let z = tilt * x - 0.05 * y + 0.16 * (x * x + y * y) - 0.04 + 0.012 * sin(Double(row * 7 + column * 3))
                return .number((z * 1000).rounded() / 1000)
            })
        }
        let axis: (Double) -> JSONValue = { size in .array((0..<rows).map { .number((Double($0) / Double(rows - 1) * size).rounded()) }) }
        return [
            "command": "@BEDLEVELVISUALIZER\nG28 W\nG80\nG81", "save_mesh": true, "timeout": 1800,
            "stored_mesh": .array(mesh), "stored_mesh_x": axis(250), "stored_mesh_y": axis(210),
            "mesh_timestamp": .string(Date.now.addingTimeInterval(-2 * 86400).formatted(date: .abbreviated, time: .shortened)),
        ]
    }

    private static let demoLog = """
    2026-06-28 14:02:11,402 - octoprint.server - INFO - Starting OctoPrint 1.10.3
    2026-06-28 14:02:14,118 - octoprint.plugins.pi_support - INFO - Detected Raspberry Pi 4 Model B Rev 1.2
    2026-06-28 14:02:19,551 - octoprint.util.comm - INFO - Changing monitoring state from "Offline" to "Opening serial connection"
    2026-06-28 14:02:21,004 - octoprint.util.comm - INFO - Changing monitoring state from "Connecting" to "Operational"
    2026-06-28 14:03:40,773 - octoprint.printer.standard.job - INFO - Print job started: gridfinity_bins_3x2_PLA.gcode
    2026-06-28 14:03:40,790 - octoprint.plugins.DisplayLayerProgress - INFO - Layer expressions found, 146 layers
    """

    /// Demo mode: nudge the print forward every half second, like OctoPrint's pushes, so live views have motion.
    private func startDemoProgress() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, var progress = self.progress else { return }
                let completion = (progress.completion ?? 0) + 0.03
                progress.completion = completion > 99.5 ? 30 : completion
                progress.printTime = (progress.printTime ?? 0) + 0.5
                progress.printTimeLeft = max(0, (progress.printTimeLeft ?? 0) - 0.5)
                self.progress = progress
            }
        }
    }

    /// A stand-in camera picture for demo mode: a print bed with a grid.
    private static func demoCameraFrame(title: String) -> Data {
        let view = ZStack {
            LinearGradient(colors: [Color(hex: 0x2A2F37), Color(hex: 0x15181C)], startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                // A bed in perspective.
                var bed = Path()
                bed.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.92))
                bed.addLine(to: CGPoint(x: size.width * 0.82, y: size.height * 0.92))
                bed.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.42))
                bed.addLine(to: CGPoint(x: size.width * 0.34, y: size.height * 0.42))
                bed.closeSubpath()
                context.fill(bed, with: .color(Color(hex: 0x3A3F47)))
                for i in 1..<8 {
                    let t = CGFloat(i) / 8
                    let bottomX = size.width * (0.18 + 0.64 * t), topX = size.width * (0.34 + 0.32 * t)
                    let line = Path { p in p.move(to: CGPoint(x: bottomX, y: size.height * 0.92)); p.addLine(to: CGPoint(x: topX, y: size.height * 0.42)) }
                    context.stroke(line, with: .color(.white.opacity(0.08)), lineWidth: 1)
                }
                // A part on the bed.
                let part = CGRect(x: size.width * 0.42, y: size.height * 0.56, width: size.width * 0.16, height: size.height * 0.18)
                context.fill(Path(roundedRect: part, cornerRadius: 4), with: .color(Color(hex: 0xF29E4C)))
            }
            VStack {
                Spacer()
                Text("Demo camera").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 10)
            }
        }
        .frame(width: 640, height: 360)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return Data() }
        return data
    }

    private static func demoFile(_ name: String, folder: String?, time: Double?, length: Double?, size: Int, daysAgo: Double, success: Bool?, model: Bool = false) -> JSONValue {
        var file: JSONValue = [
            "name": .string(name), "display": .string(name),
            "path": .string(folder.map { "\($0)/\(name)" } ?? name),
            "type": model ? "model" : "machinecode", "origin": "local", "size": JSONValue(size),
            "date": JSONValue(Date.now.addingTimeInterval(-daysAgo * 86400).timeIntervalSince1970),
        ]
        if case .object(var object) = file {
            if let time, let length {
                object["gcodeAnalysis"] = ["estimatedPrintTime": JSONValue(time), "filament": ["tool0": ["length": JSONValue(length)]]]
            }
            if let success {
                object["prints"] = ["success": .number(success ? 3 : 1), "failure": .number(success ? 0 : 1), "last": [
                    "success": .bool(success),
                    "date": .number(Date.now.addingTimeInterval(-daysAgo * 86400 - 3600).timeIntervalSince1970),
                    "printTime": .number((time ?? 3600) * (success ? 1.04 : 0.4)),
                ]]
            }
            file = .object(object)
        }
        return file
    }

    private static let demoTerminal: [String] = [
        "Send: N4120 G1 X112.402 Y98.611 E0.04121*91",
        "Recv: ok",
        "Send: N4121 G1 X113.950 Y98.611 E0.05207*88",
        "Recv: ok",
        "Send: M105",
        "Recv: ok T:214.6 /215.0 B:60.1 /60.0 T0:214.6 /215.0 @:62 B@:31",
        "Send: N4122 G1 X113.950 Y102.004 E0.11433*80",
        "Recv: ok",
        "Send: M117 63% Layer 92/146",
        "Recv: ok",
        "Send: N4123 G1 F2400 X98.200 Y102.004*41",
        "Recv: ok",
        "Recv: echo:busy: processing",
        "Send: N4124 G1 Z18.400 F720*72",
        "Recv: ok",
    ]
}
