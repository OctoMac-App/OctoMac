import Foundation
import OctoPrintKit

/// What OctoMac remembers about a printer besides its connection: a scheduled start, the print queue, your notes on
/// files, and past bed meshes. One small file per printer in `~/Library/Application Support/OctoMac/Printers/`.
struct PrinterJournal: Codable, Equatable {
    /// A file to print later, at `start`.
    struct Scheduled: Codable, Equatable {
        var path: String
        var origin: String
        var name: String
        var start: Date
        /// When it should be done, at the file's usual print time.
        var finish: Date
    }

    /// A file waiting its turn.
    struct Queued: Codable, Equatable, Identifiable {
        var id = UUID()
        var path: String
        var origin: String
        var name: String
    }

    /// Your rating (1 to 5) and note on a file.
    struct Note: Codable, Equatable {
        var rating: Int?
        var text = ""
        var isEmpty: Bool { rating == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// A bed mesh as measured on a day.
    struct Mesh: Codable, Equatable, Identifiable {
        var date: Date
        var z: [[Double?]]
        var x: [Double]
        var y: [Double]
        var id: Date { date }

        var mesh: BedLevelVisualizer.Mesh {
            BedLevelVisualizer.Mesh(z: z, x: x, y: y, measured: date.formatted(date: .abbreviated, time: .shortened))
        }
    }

    var scheduled: Scheduled?
    var queue: [Queued] = []
    /// Keyed by the file's path on the printer.
    var notes: [String: Note] = [:]
    /// Oldest first.
    var meshes: [Mesh] = []

    static let meshLimit = 40

    // MARK: Saving

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "OctoMac/Printers")
    }

    private static func url(for id: UUID) -> URL { directory.appending(path: "\(id.uuidString).json") }

    static func load(for id: UUID) -> PrinterJournal {
        guard let data = try? Data(contentsOf: url(for: id)) else { return PrinterJournal() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PrinterJournal.self, from: data)) ?? PrinterJournal()
    }

    func save(for id: UUID) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        if let data = try? encoder.encode(self) { try? data.write(to: Self.url(for: id), options: .atomic) }
    }

    static func remove(for id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }
}

extension BedLevelVisualizer.Mesh {
    /// How much each point has moved since `earlier`, when both were measured on the same grid.
    func change(since earlier: BedLevelVisualizer.Mesh) -> BedLevelVisualizer.Mesh? {
        guard z.count == earlier.z.count, zip(z, earlier.z).allSatisfy({ $0.count == $1.count }) else { return nil }
        let difference = zip(z, earlier.z).map { now, then in
            zip(now, then).map { a, b -> Double? in
                guard let a, let b else { return nil }
                return a - b
            }
        }
        return BedLevelVisualizer.Mesh(z: difference, x: x, y: y, measured: measured)
    }
}
