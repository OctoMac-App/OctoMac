import Foundation

/// What OctoMac shares with its widgets: a small status file the app rewrites as printers change, read by the
/// sandboxed widget extension. Lives in `~/Library/Application Support/OctoMac/Widgets/`.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct Printer: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var name: String
        /// The printer's colour in OctoMac, e.g. `#8F7CFF`.
        public var colorHex: String?
        public var status: Status
        /// "Printing", "Ready", "Printer not connected"…
        public var statusText: String
        /// The print's readable name, while there is one.
        public var job: String?
        /// 0 to 1.
        public var progress: Double?
        /// Seconds left when the snapshot was taken.
        public var timeLeft: Double?
        public var hotend: Double?
        public var hotendTarget: Double?
        public var bed: Double?
        public var bedTarget: Double?
        public var hasCamera: Bool

        public init(id: UUID, name: String, colorHex: String?, status: Status, statusText: String, job: String?, progress: Double?,
                    timeLeft: Double?, hotend: Double?, hotendTarget: Double?, bed: Double?, bedTarget: Double?, hasCamera: Bool) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
            self.status = status
            self.statusText = statusText
            self.job = job
            self.progress = progress
            self.timeLeft = timeLeft
            self.hotend = hotend
            self.hotendTarget = hotendTarget
            self.bed = bed
            self.bedTarget = bedTarget
            self.hasCamera = hasCamera
        }
    }

    public enum Status: String, Codable, Sendable {
        case printing, paused, ready, offline, problem
    }

    public var written: Date
    public var printers: [Printer]
    /// "celsius" or "fahrenheit".
    public var temperatureUnit: String

    public init(written: Date, printers: [Printer], temperatureUnit: String) {
        self.written = written
        self.printers = printers
        self.temperatureUnit = temperatureUnit
    }

    /// The printer most worth showing on its own: one that's printing, then paused, then any.
    public var featured: Printer? {
        printers.first { $0.status == .printing } ?? printers.first { $0.status == .paused } ?? printers.first
    }

    // MARK: Files

    /// The folder in the user's real home (not a sandbox container), so the app and the widget agree on it.
    public static var folder: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appending(path: "Library/Application Support/OctoMac/Widgets", directoryHint: .isDirectory)
    }

    public static var fileURL: URL { folder.appending(path: "status.json") }
    public static func cameraURL(for id: UUID) -> URL { folder.appending(path: "camera-\(id.uuidString).jpg") }

    public static func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(self).write(to: Self.fileURL, options: .atomic)
    }
}

extension WidgetSnapshot.Printer {
    /// Progress and time left as they'll be at `date`, assuming the print carries on at the same pace.
    public func projected(to date: Date, from written: Date) -> (progress: Double?, timeLeft: Double?) {
        guard status == .printing, let progress, let timeLeft, timeLeft > 0 else { return (progress, timeLeft) }
        let elapsed = max(0, date.timeIntervalSince(written))
        let left = max(0, timeLeft - elapsed)
        let done = progress + (1 - progress) * min(1, elapsed / timeLeft)
        return (min(1, done), left)
    }
}
