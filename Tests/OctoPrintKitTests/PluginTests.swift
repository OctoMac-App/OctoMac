import Foundation
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
        #expect(blv.canMeasure)
        #expect(BedLevelVisualizer.Settings(settings: ["plugins": ["bedlevelvisualizer": ["command": ""]]])?.canMeasure == false)
        #expect(BedLevelVisualizer.Settings(settings: ["plugins": ["bedlevelvisualizer": ["command": "@BEDLEVELVISUALIZER\n"]]])?.canMeasure == false)
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

struct CustomControlTests {
    @Test func parsesGroupsInputsAndScripts() {
        let json: JSONValue = ["controls": [
            ["name": "Filament", "children": [
                ["name": "Load", "commands": ["M701"], "confirm": "Is the hotend hot?"],
                ["name": "Set fan", "command": "M106 S%(speed)s", "input": [["name": "Speed", "parameter": "speed", "default": 255]]],
            ]],
            ["name": "Wipe", "script": "wipe_nozzle"],
            ["name": "Broken"],
        ]]
        let controls = CustomControl.parse(json)
        #expect(controls.count == 2)
        guard case .group(let name, let children) = controls[0], case .action(let fan) = children[1] else {
            Issue.record("expected a group with a fan control"); return
        }
        #expect(name == "Filament")
        #expect(fan.resolvedCommands([:]) == ["M106 S255"])
        #expect(fan.resolvedCommands(["speed": "128"]) == ["M106 S128"])
        guard case .action(let wipe) = controls[1] else { Issue.record("expected a script"); return }
        #expect(wipe.script == "wipe_nozzle")
    }

    @Test func webcams() {
        let settings: JSONValue = ["webcam": ["webcams": [
            ["name": "classic", "displayName": "Classic Webcam", "compat": ["stream": "/webcam/?action=stream"], "flipH": true],
            ["name": "side", "displayName": "Side", "extras": ["stream": "http://cam2/stream"]],
            ["name": "nostream", "displayName": "Snapshot only"],
        ]]]
        let cams = Webcam.list(from: settings)
        #expect(cams.map(\.name) == ["classic", "side"])
        #expect(cams[0].flipH)
        #expect(Webcam.list(from: ["webcam": ["streamUrl": "/webcam/"]]).first?.stream == "/webcam/")
    }
}

struct CancelObjectTests {
    @Test func objectsMessage() {
        let message = CancelObject.message(["objects": [
            ["object": "bin_3x2.stl_id_0_copy_0", "id": 0, "active": true, "cancelled": false, "ignore": false,
             "min_x": 40.5, "max_x": 120.0, "min_y": 30.0, "max_y": 90.0],
            ["object": "purge", "id": 1, "cancelled": false, "ignore": true, "min_x": 10000, "max_x": 0, "min_y": 10000, "max_y": 0],
            ["object": "Shape-Box", "id": 2, "cancelled": true],
        ]])
        guard case .objects(let objects) = message else { Issue.record("expected objects"); return }
        #expect(objects.count == 3)
        #expect(objects[0].displayName == "bin 3x2, copy 1")
        #expect(objects[0].bounds == .init(minX: 40.5, minY: 30, maxX: 120, maxY: 90))
        #expect(objects[1].ignored && objects[1].bounds == nil)
        #expect(objects[2].cancelled)
        #expect(CancelObject.message(["ActiveID": 2]) == .active(2))
        #expect(CancelObject.message(["navBarActive": "x"]) == nil)
    }
}

struct PrintTimeTests {
    private func file(_ analysis: JSONValue?, average: Double? = nil) throws -> FileEntry {
        var json: [String: JSONValue] = ["name": "a.gcode", "path": "a.gcode", "type": "machinecode", "origin": "local"]
        if let analysis { json["gcodeAnalysis"] = analysis }
        if let average { json["statistics"] = ["averagePrintTime": ["_default": .number(average)]] }
        return try JSONValue.object(json).decode(FileEntry.self)
    }

    @Test func prefersPrintTimeGeniusThenOctoPrintThenPastPrints() throws {
        let genius = try file(["estimatedPrintTime": 5799, "compensatedPrintTime": 5799, "analysisPrintTime": 5517])
        #expect(genius.expectedPrintTime?.source == .printTimeGenius)
        let plain = try file(["estimatedPrintTime": 4200])
        #expect(plain.expectedPrintTime?.seconds == 4200 && plain.expectedPrintTime?.source == .octoPrint)
        let history = try file(nil, average: 3600)
        #expect(history.expectedPrintTime?.source == .pastPrints)
        #expect(try file(nil).expectedPrintTime == nil)
    }
}

struct PluginManagerTests {
    @Test func readsInstalledPlugins() throws {
        let json: JSONValue = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"key": "cancelobject", "name": "Cancel Objects", "version": "0.5.0", "author": "Paul", "description": "Cancel parts",
         "url": "https://github.com/paukstelis/Octoprint-Cancelobject", "enabled": false, "bundled": false, "managable": true,
         "pending_enable": true, "safe_mode_victim": false}
        """.utf8))
        let plugin = try #require(InstalledPlugin(json))
        #expect(plugin.key == "cancelobject")
        #expect(plugin.summary == "Cancel parts")
        #expect(!plugin.enabled)
        #expect(plugin.pending)
        #expect(plugin.homepage?.host() == "github.com")
    }

    @Test func readsRepositoryPlugins() throws {
        let json: JSONValue = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"id": "bedlevelvisualizer", "title": "Bed Level Visualizer", "description": "Displays 3D mesh.", "author": "jneilliii",
         "archive": "https://github.com/jneilliii/OctoPrint-BedLevelVisualizer/archive/master.zip",
         "page": "https://plugins.octoprint.org/plugins/bedlevelvisualizer/", "follow_dependency_links": false,
         "is_compatible": {"octoprint": true, "os": true, "python": false}, "attributes": ["abandoned"],
         "stats": {"instances_month": 14709}}
        """.utf8))
        let plugin = try #require(RepositoryPlugin(json))
        #expect(plugin.title == "Bed Level Visualizer")
        #expect(plugin.archive.lastPathComponent == "master.zip")
        #expect(!plugin.compatible)
        #expect(plugin.abandoned)
        #expect(plugin.users == 14709)
        #expect(RepositoryPlugin(["id": "noarchive"]) == nil)
    }

    @Test func readsInstallProgress() {
        #expect(PluginManagerMessage(["type": "loglines", "loglines": [["line": "Collecting x", "stream": "stdout"]]]) == .log(["Collecting x"]))
        let done = PluginManagerMessage(["type": "result", "action": "install", "result": true, "needs_restart": true])
        #expect(done == .result(action: "install", success: true, needsRestart: true, reason: nil, plugin: nil))
        let failed = PluginManagerMessage(["type": "result", "action": "install", "result": false, "reason": "Pip reported a Python version mismatch"])
        #expect(failed == .result(action: "install", success: false, needsRestart: false, reason: "Pip reported a Python version mismatch", plugin: nil))
        #expect(PluginManagerMessage(["type": "partial_result", "action": "install"]) == nil)
    }
}

struct BackupTests {
    @Test func readsBackupsNewestFirst() {
        let state = Backup.state([
            "backups": [
                ["name": "octoprint-backup-20261001-200311.zip", "date": 1_790_000_000, "size": 41_207_118, "url": "/plugin/backup/download/a.zip"],
                ["name": "octoprint-backup-20261026-091542.zip", "date": 1_792_000_000, "size": 46_812_330],
            ],
            "backup_in_progress": true,
        ])
        #expect(state.inProgress)
        #expect(state.backups.map(\.name) == ["octoprint-backup-20261026-091542.zip", "octoprint-backup-20261001-200311.zip"])
        #expect(state.backups.first?.size == 46_812_330)
        #expect(Backup.state([:]).backups.isEmpty)
    }

    @Test func readsBackupMessages() {
        #expect(Backup.Message(["type": "backup_started", "name": "b.zip"]) == .started("b.zip"))
        #expect(Backup.Message(["type": "backup_done", "name": "b.zip"]) == .done("b.zip"))
        #expect(Backup.Message(["type": "backup_error", "name": "b.zip", "error": "Not enough space"]) == .failed(name: "b.zip", error: "Not enough space"))
        #expect(Backup.Message(["type": "unknown_plugins"]) == nil)
    }
}
