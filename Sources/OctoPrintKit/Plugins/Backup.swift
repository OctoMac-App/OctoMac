import Foundation

/// OctoPrint's bundled Backup & Restore plugin: https://docs.octoprint.org/en/main/bundledplugins/backup.html
///
/// A backup is a zip of OctoPrint's settings, plugins and data, kept on the Raspberry Pi. Making one runs in the
/// background, and the plugin pushes `backup_started`, then `backup_done` or `backup_error`. Restoring isn't offered
/// here: OctoPrint asks for the password again and restarts, which is best done on its own page.
public enum Backup {
    public static let pluginID = "backup"

    /// Folders a backup can leave out, as the plugin names them.
    public enum Part: String, Sendable, CaseIterable {
        /// G-code files and their metadata.
        case uploads
        case timelapse
    }

    public struct File: Sendable, Hashable, Identifiable {
        public var name: String
        public var date: Date?
        public var size: Int64

        public var id: String { name }

        public init(name: String, date: Date? = nil, size: Int64 = 0) {
            self.name = name
            self.date = date
            self.size = size
        }

        init?(_ json: JSONValue) {
            guard let name = json["name"]?.stringValue else { return nil }
            self.init(name: name, date: json["date"]?.doubleValue.map(Date.init(timeIntervalSince1970:)),
                      size: Int64(json["size"]?.doubleValue ?? 0))
        }
    }

    public struct State: Sendable, Hashable {
        /// Newest first.
        public var backups: [File]
        public var inProgress: Bool

        public init(backups: [File], inProgress: Bool) {
            self.backups = backups
            self.inProgress = inProgress
        }
    }

    public enum Message: Sendable, Equatable {
        case started(String)
        case done(String)
        case failed(name: String, error: String)

        public init?(_ data: JSONValue) {
            let name = data["name"]?.stringValue ?? ""
            switch data["type"]?.stringValue {
            case "backup_started": self = .started(name)
            case "backup_done": self = .done(name)
            case "backup_error": self = .failed(name: name, error: data["error"]?.stringValue ?? "")
            default: return nil
            }
        }
    }

    static func state(_ json: JSONValue) -> State {
        let backups = (json["backups"]?.arrayValue ?? []).compactMap(File.init)
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return State(backups: backups, inProgress: json["backup_in_progress"]?.boolValue ?? false)
    }
}

extension OctoPrintClient {
    /// The backups on the Pi, and whether one is being made.
    public func backupState() async throws -> Backup.State {
        Backup.state(try await get("plugin/\(Backup.pluginID)/"))
    }

    /// Starts a backup, leaving out the given parts. It's made in the background; watch for `Backup.Message`.
    public func createBackup(excluding parts: [Backup.Part] = []) async throws {
        let body: CommandBody = ["exclude": .array(parts.map { .string($0.rawValue) })]
        try await post("plugin/\(Backup.pluginID)/backup", body: body)
    }

    public func deleteBackup(_ file: Backup.File) async throws {
        try await delete("plugin/\(Backup.pluginID)/backup/\(file.name)")
    }

    /// Downloads a backup straight to a file, since they can be large. Reports progress from 0 to 1.
    public func downloadBackup(_ file: Backup.File, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let request = makeRequest(.get, "plugin/\(Backup.pluginID)/download/\(file.name)")
        let delegate = DownloadProgressDelegate(expected: file.size, onProgress: progress)
        let (location, response) = try await session.download(for: request, delegate: delegate)
        guard let http = response as? HTTPURLResponse else { throw OctoPrintError.invalidResponse }
        try Self.check(http, data: http.statusCode < 300 ? Data() : (try? Data(contentsOf: location)) ?? Data())
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: location, to: destination)
    }
}

/// Follows a download's progress. (The download delegate's own progress callback isn't called for async downloads.)
final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let expected: Int64
    private let onProgress: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(expected: Int64, onProgress: @escaping @Sendable (Double) -> Void) {
        self.expected = expected
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.completedUnitCount) { [expected, onProgress] progress, _ in
            // OctoPrint doesn't always say how big the file is; the backup list does.
            let total = progress.totalUnitCount > 0 ? progress.totalUnitCount : expected
            guard total > 0 else { return }
            onProgress(min(Double(progress.completedUnitCount) / Double(total), 1))
        }
    }
}
