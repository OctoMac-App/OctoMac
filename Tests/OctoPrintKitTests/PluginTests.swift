import Testing
@testable import OctoPrintKit

struct DisplayLayerProgressTests {
    @Test func pushPayload() {
        let progress = LayerProgress(push: [
            "currentLayer": "71", "totalLayer": "120", "currentHeight": "14.20", "totalHeight": "24.0",
            "averageLayerDurationInSeconds": "62", "lastLayerDurationInSeconds": "-", "changeFilamentCount": 0,
        ])
        #expect(progress.currentLayer == 71)
        #expect(progress.totalLayers == 120)
        #expect(progress.averageLayerDuration == 62)
        #expect(progress.lastLayerDuration == nil)
        #expect(progress.hasLayers)
    }

    @Test func idleValues() {
        let progress = LayerProgress(values: ["layer": ["current": "-", "total": "-"], "height": ["current": "-"]])
        #expect(progress.currentLayer == nil)
        #expect(!progress.hasLayers)
    }
}

struct BedLevelVisualizerTests {
    @Test func meshMessage() throws {
        let message = BedLevelVisualizer.Message([
            "mesh": [["0.1", "-0.05", "0"], ["0.2", "0.0", "-0.1"]],
            "bed": ["x_min": 0, "x_max": 250, "y_min": 0, "y_max": 210, "type": "rectangular"],
        ])
        guard case .mesh(let mesh) = message else { Issue.record("expected a mesh"); return }
        #expect(mesh.x == [0, 125, 250])
        #expect(mesh.y == [0, 210])
        #expect(mesh.minimum == -0.1)
        #expect(abs((mesh.spread ?? 0) - 0.3) < 0.0001)
    }

    @Test func otherMessages() {
        #expect(BedLevelVisualizer.Message(["processing": true]) == .processing)
        #expect(BedLevelVisualizer.Message(["error": "Home XYZ first"]) == .error("Home XYZ first"))
        #expect(BedLevelVisualizer.Message(["timeout_override": "300"]) == nil)
    }

    @Test func settings() throws {
        let settings: JSONValue = ["plugins": ["bedlevelvisualizer": [
            "command": "G28 W\nG80\n\nG81", "save_mesh": true, "timeout": 1800,
            "stored_mesh": [[0.1, 0.2], [nil, 0.3]], "stored_mesh_x": [0, 250], "stored_mesh_y": [0, 210],
            "mesh_timestamp": "28/10/2026, 15:00:00",
        ]]]
        let blv = try #require(BedLevelVisualizer.Settings(settings: settings))
        #expect(blv.commandLines == ["G28 W", "G80", "G81"])
        #expect(blv.stored?.z[1][0] == nil)
        #expect(blv.stored?.maximum == 0.3)
        #expect(BedLevelVisualizer.Settings(settings: ["plugins": ["bedlevelvisualizer": ["stored_mesh": []]]])?.stored == nil)
    }
}

struct SystemHealthTests {
    @Test func throttle() throws {
        let info = PiSupportInfo(["model": "Raspberry Pi 4 Model B Rev 1.2", "throttle_state": [
            "current_issue": false, "past_issue": true, "past_undervoltage": true, "raw_value": 0x50000,
        ]])
        let throttle = try #require(info.throttle)
        #expect(throttle.pastUndervoltage)
        #expect(!throttle.currentIssue)
        #expect(PiSupportInfo.throttleUpdate(["type": "throttle_state", "state": ["current_issue": true, "current_overheat": true]])?.currentOverheat == true)
    }

    @Test func printerError() {
        #expect(PrinterErrorInfo(["error": "", "reason": ""]).isEmpty)
        let info = PrinterErrorInfo(["error": "No more candidates to test", "reason": "autodetect", "consequence": "disconnect"])
        #expect(info.reason == "autodetect")
    }
}
