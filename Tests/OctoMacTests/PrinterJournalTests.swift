import Foundation
import Testing
@testable import OctoMac
@testable import OctoPrintKit

struct PrinterJournalTests {
    @Test func survivesSavingAndLoading() throws {
        var journal = PrinterJournal()
        journal.scheduled = .init(path: "a.gcode", origin: "local", name: "a", start: Date(timeIntervalSince1970: 1_780_000_000),
                                  finish: Date(timeIntervalSince1970: 1_780_007_200))
        journal.queue = [.init(path: "b.gcode", origin: "local", name: "b")]
        journal.notes["a.gcode"] = .init(rating: 4, text: "Needs a brim")
        journal.meshes = [.init(date: Date(timeIntervalSince1970: 1_779_000_000), z: [[0.1, nil], [0.2, -0.1]], x: [0, 200], y: [0, 200])]

        let id = UUID()
        defer { PrinterJournal.remove(for: id) }
        journal.save(for: id)
        #expect(PrinterJournal.load(for: id) == journal)
    }

    @Test func emptyNotesAreNotKept() {
        #expect(PrinterJournal.Note().isEmpty)
        #expect(PrinterJournal.Note(rating: nil, text: "  \n").isEmpty)
        #expect(!PrinterJournal.Note(rating: 2).isEmpty)
    }

    @Test func meshChangeIsPointByPoint() throws {
        let then = BedLevelVisualizer.Mesh(z: [[0.10, 0.20], [nil, -0.10]], x: [0, 200], y: [0, 200])
        let now = BedLevelVisualizer.Mesh(z: [[0.15, 0.20], [0.30, -0.25]], x: [0, 200], y: [0, 200])
        let change = try #require(now.change(since: then))
        #expect(abs((change.z[0][0] ?? 0) - 0.05) < 0.0001)
        #expect(change.z[0][1] == 0)
        #expect(change.z[1][0] == nil)
        #expect(abs((change.z[1][1] ?? 0) + 0.15) < 0.0001)
        // Different probe grids can't be compared.
        #expect(now.change(since: BedLevelVisualizer.Mesh(z: [[0.1]], x: [0], y: [0])) == nil)
    }

    @Test @MainActor func readsTheDatesStoredWithMeshes() throws {
        let ours = Date.now.formatted(date: .abbreviated, time: .shortened)
        #expect(PrinterSession.meshDate(ours) != nil)
        let plugin = try #require(PrinterSession.meshDate("10/28/2026, 4:09:54 PM"))
        #expect(Calendar(identifier: .gregorian).component(.day, from: plugin) == 28)
        // The plugin's page writes the date in the browser's language, for example UK English.
        let british = try #require(PrinterSession.meshDate("29/10/2026, 13:18:46"))
        #expect(Calendar(identifier: .gregorian).dateComponents([.day, .month, .hour], from: british) == DateComponents(month: 10, day: 29, hour: 13))
        #expect(PrinterSession.meshDate("") == nil)
    }
}
