import Foundation
import Testing
@testable import OctoMac

struct PrintStatisticsTests {
    @Test func logAndLatestPrintsDoNotCountTwice() {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let log = [PrintRecord(path: "a.gcode", date: date, duration: 3600, success: true, filament: 1000)]
        let latest = [
            PrintRecord(path: "a.gcode", date: date.addingTimeInterval(20), duration: 3600, success: true, filament: 1000),
            PrintRecord(path: "b.gcode", date: date, duration: 600, success: false, filament: nil),
        ]
        let merged = PrintStatistics.merge(log: log, latest: latest)
        #expect(merged.count == 2)

        let months = PrintStatistics.months(merged, now: date, count: 3)
        #expect(months.count == 3)
        #expect(months.last?.finished == 1)
        #expect(months.last?.failed == 1)
        #expect(abs((months.last?.hours ?? 0) - (4200.0 / 3600)) < 0.001)
    }
}
