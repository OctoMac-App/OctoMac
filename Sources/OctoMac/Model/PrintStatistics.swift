import Foundation
import OctoPrintKit

/// One print OctoMac knows about: either one it saw finish or fail, or a file's latest print from OctoPrint.
struct PrintRecord: Codable, Hashable, Sendable {
    var path: String
    var date: Date
    var duration: TimeInterval?
    var success: Bool
    /// Filament used, in millimetres, when the file's analysis knows it.
    var filament: Double?
}

/// A record of the prints OctoMac has watched finish or fail, one file per printer in
/// `~/Library/Application Support/OctoMac/History/`. OctoPrint only remembers each file's latest print, so this is
/// what lets statistics show every print month by month, from when you started using OctoMac.
enum PrintLog {
    private static let limit = 5000

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "OctoMac/History")
    }

    private static func url(for id: UUID) -> URL { directory.appending(path: "\(id.uuidString).json") }

    static func records(for id: UUID) -> [PrintRecord] {
        guard let data = try? Data(contentsOf: url(for: id)) else { return [] }
        return (try? JSONDecoder().decode([PrintRecord].self, from: data)) ?? []
    }

    static func append(_ record: PrintRecord, for id: UUID) {
        var records = records(for: id)
        records.append(record)
        if records.count > limit { records.removeFirst(records.count - limit) }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) { try? data.write(to: url(for: id), options: .atomic) }
    }

    static func remove(for id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }
}

/// Totals and a month-by-month picture of a printer's prints.
///
/// Totals come from OctoPrint's own counts for each file, so they cover the printer's whole life. Printing time and
/// filament are worked out from finished prints: each file's usual print time and filament length, times how often
/// it finished. Months combine OctoMac's own log with each file's latest print from OctoPrint.
struct PrintStatistics {
    struct Month: Identifiable, Hashable {
        var start: Date
        var finished = 0
        var failed = 0
        var hours = 0.0
        var id: Date { start }
        var total: Int { finished + failed }
    }

    struct Favourite: Hashable {
        var name: String
        var count: Int
    }

    var finished = 0
    var failed = 0
    var printingTime: TimeInterval = 0
    /// Millimetres.
    var filament: Double = 0
    var months: [Month] = []
    var favourites: [Favourite] = []

    var total: Int { finished + failed }
    var successRate: Double? { total == 0 ? nil : Double(finished) / Double(total) }

    init(files: [FileEntry], log: [PrintRecord], now: Date = .now, monthsShown: Int = 12) {
        let all = Self.flatten(files)
        var latest: [PrintRecord] = []
        for file in all {
            let finishedCount = file.prints?.success ?? 0
            finished += finishedCount
            failed += file.prints?.failure ?? 0
            let usual = file.expectedPrintTime?.seconds ?? file.prints?.last?.printTime ?? 0
            printingTime += Double(finishedCount) * usual
            filament += Double(finishedCount) * (file.gcodeAnalysis?.totalFilamentLength ?? 0)
            let count = finishedCount + (file.prints?.failure ?? 0)
            if count > 0 { favourites.append(Favourite(name: SlicedName(file.displayName).title, count: count)) }
            if let last = file.prints?.last, let date = last.date, let success = last.success {
                latest.append(PrintRecord(path: file.path, date: Date(timeIntervalSince1970: date), duration: last.printTime,
                                          success: success, filament: file.gcodeAnalysis?.totalFilamentLength))
            }
        }
        favourites = Array(favourites.sorted { $0.count > $1.count }.prefix(3))
        months = Self.months(Self.merge(log: log, latest: latest), now: now, count: monthsShown)
    }

    /// OctoMac's log plus any latest print from OctoPrint that the log doesn't already have (same file, within a few
    /// minutes), for prints made before OctoMac was watching.
    static func merge(log: [PrintRecord], latest: [PrintRecord]) -> [PrintRecord] {
        log + latest.filter { last in
            !log.contains { $0.path == last.path && abs($0.date.timeIntervalSince(last.date)) < 300 }
        }
    }

    static func months(_ records: [PrintRecord], now: Date, count: Int) -> [Month] {
        let calendar = Calendar.current
        guard let thisMonth = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        var months = (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: thisMonth).map { Month(start: $0) }
        }
        for record in records {
            guard let start = calendar.dateInterval(of: .month, for: record.date)?.start,
                  let index = months.firstIndex(where: { $0.start == start }) else { continue }
            if record.success { months[index].finished += 1 } else { months[index].failed += 1 }
            months[index].hours += (record.duration ?? 0) / 3600
        }
        return months
    }

    private static func flatten(_ entries: [FileEntry]) -> [FileEntry] {
        entries.flatMap { $0.isFolder ? flatten($0.children ?? []) : [$0] }
    }
}

extension PrintStatistics {
    /// Several printers' statistics added together.
    init(combining parts: [PrintStatistics]) {
        self.init(files: [], log: [])
        finished = parts.reduce(0) { $0 + $1.finished }
        failed = parts.reduce(0) { $0 + $1.failed }
        printingTime = parts.reduce(0) { $0 + $1.printingTime }
        filament = parts.reduce(0) { $0 + $1.filament }
        months = parts.first?.months.indices.map { index in
            var month = Month(start: parts[0].months[index].start)
            for part in parts where part.months.indices.contains(index) {
                month.finished += part.months[index].finished
                month.failed += part.months[index].failed
                month.hours += part.months[index].hours
            }
            return month
        } ?? []
        var counts: [String: Int] = [:]
        for part in parts { for favourite in part.favourites { counts[favourite.name, default: 0] += favourite.count } }
        favourites = Array(counts.map { Favourite(name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }.prefix(3))
    }
}
