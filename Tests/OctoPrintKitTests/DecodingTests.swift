import Foundation
import Testing
@testable import OctoPrintKit

/// Decoding against payloads shaped like real OctoPrint 1.11 responses (Prusa MK3S with PrusaSlicer Thumbnails).
struct DecodingTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func fileListWithFoldersThumbnailsAndHistory() throws {
        let list = try JSONDecoder().decode(FileList.self, from: fixture("files"))
        #expect(list.files.count == 2)
        #expect(list.free == 54_430_000_000)

        let folder = try #require(list.files.first)
        #expect(folder.isFolder)
        let file = try #require(folder.children?.first)
        #expect(file.isMachineCode)
        #expect(file.path == "workshop/6-piece-hook-set_0.2mm_PETG_MK3S_2h16m.gcode")
        #expect(file.thumbnail?.hasPrefix("plugin/prusaslicerthumbnails/") == true)
        #expect(file.gcodeAnalysis?.estimatedPrintTime == 8313.44)
        #expect(file.gcodeAnalysis?.totalFilamentLength == 9522.41)
        #expect(file.prints?.failure == 3)
        #expect(file.prints?.last?.success == false)

        let model = list.files[1]
        #expect(model.isModel)
        #expect(model.children == nil)
    }

    @Test func currentPushMessage() throws {
        let messages = try PushMessage.parse(fixture("current"))
        guard case .current(let payload) = try #require(messages.first) else {
            Issue.record("Expected a current message")
            return
        }
        #expect(payload.state?.flags.printing == true)
        #expect(payload.state?.flags.isJobActive == true)
        #expect(payload.progress?.fraction == 0.634)
        #expect(payload.job?.file.displayName == "pet_guard.gcode")
        #expect(payload.job?.filament["tool0"]?.length == 11030)
        #expect(payload.currentZ == 18.4)
        #expect(payload.logs.count == 2)

        let temps = try #require(payload.temps.first)
        #expect(temps.heaters["tool0"]?.target == 215)
        #expect(temps.heaters["A"]?.actual == 34.2)
        #expect(temps.time != nil)
    }

    @Test func heaterKinds() {
        #expect(HeaterKind(key: "tool0") == .tool(0))
        #expect(HeaterKind(key: "tool1").displayName == "Hotend 2")
        #expect(HeaterKind(key: "bed").isHeater)
        #expect(HeaterKind(key: "A") == .ambient)
        #expect(HeaterKind(key: "P").isHeater == false)
    }

    @Test func missingFlagsDefaultToFalse() throws {
        let state = try JSONDecoder().decode(PrinterState.self, from: Data(#"{"text": "Offline", "flags": {"closedOrError": true}}"#.utf8))
        #expect(state.flags.closedOrError)
        #expect(!state.flags.operational)
        #expect(!state.flags.isJobActive)
    }

    @Test func jsonValueRoundTripKeepsIntegers() throws {
        let body: CommandBody = ["command": "connect", "baudrate": 115200, "save": false]
        let encoded = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        #expect(encoded.contains("\"baudrate\":115200"))
    }

    @Test func eventMessage() throws {
        let messages = try PushMessage.parse(Data(#"{"event": {"type": "PrintCancelled", "payload": {"name": "x.gcode"}}}"#.utf8))
        guard case .event(let event) = try #require(messages.first) else {
            Issue.record("Expected an event")
            return
        }
        #expect(event.type == "PrintCancelled")
        #expect(event.payload["name"]?.stringValue == "x.gcode")
    }
}
