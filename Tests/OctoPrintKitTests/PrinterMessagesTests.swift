import Foundation
import Testing
@testable import OctoPrintKit

struct PrinterMessagesTests {
    @Test func readsPrinterQuestions() {
        let show = ActionPrompt.Message(["action": "show", "text": "Filament runout", "choices": ["Continue", "Purge more"]])
        #expect(show == .show(.init(text: "Filament runout", choices: ["Continue", "Purge more"])))
        #expect(ActionPrompt.Message(["action": "close"]) == .close)
        #expect(ActionPrompt.Message(["action": "other"]) == nil)
        // No question waiting: the plugin answers with an empty object.
        #expect(ActionPrompt.Prompt([:] as JSONValue) == nil)
    }

    @Test func readsPrinterNotifications() {
        #expect(ActionNotification.Message(["message": "Heating done"]) == .added("Heating done"))
        #expect(ActionNotification.Message([:]) == .cleared)
        let notes = ActionNotification.notes(["notifications": [["timestamp": 1_780_000_000, "message": "Heating done"]]])
        #expect(notes.map(\.message) == ["Heating done"])
        #expect(notes.first?.date == Date(timeIntervalSince1970: 1_780_000_000))
    }

    @Test func readsHealthChecks() {
        let items = HealthCheck.items(["health": [
            "filesystem_storage": ["result": "warning", "context": ["uploads": 88.4], "hash": "abc"],
            "python_eol": ["result": "ok", "context": [:], "hash": "def"],
        ]])
        #expect(items.map(\.key) == ["filesystem_storage", "python_eol"])
        #expect(items.first?.result == .warning)
        #expect(items.first?.context["uploads"]?.doubleValue == 88.4)
    }

    @Test func readsFirmwareWarnings() {
        let warnings = FirmwareCheck.warnings([
            "firmware-unsafe": ["message": "Your printer's firmware is known to lack mandatory safety features", "severity": "critical",
                                "url": "https://faq.octoprint.org/warning-firmware-unsafe"],
            "firmware-development": ["message": "Development firmware", "severity": "info"],
        ])
        #expect(warnings.map(\.type) == ["firmware-development", "firmware-unsafe"])
        #expect(warnings[1].isCritical && !warnings[0].isCritical)
        #expect(warnings[1].url?.host == "faq.octoprint.org")
    }

    @Test func readsSoftwareUpdateProgress() {
        #expect(SoftwareUpdateMessage(["type": "loglines", "data": ["loglines": [["line": "Collecting OctoPrint", "stream": "stdout"]]]])
            == .log(["Collecting OctoPrint"]))
        #expect(SoftwareUpdateMessage(["type": "update_failed", "data": ["target": "octoprint", "reason": "No space left"]])
            == .failed(target: "octoprint", reason: "No space left"))
        #expect(SoftwareUpdateMessage(["type": "restarting", "data": [:]]) == .restarting)
        #expect(SoftwareUpdateMessage(["type": "update_versions", "data": [:]]) == nil)
    }

    @Test func readsRestoreProgress() {
        #expect(Backup.Message(["type": "restore_started"]) == .restoreStarted)
        #expect(Backup.Message(["type": "logline", "line": "Restoring settings", "stream": "stdout"]) == .restoreLog("Restoring settings"))
        #expect(Backup.Message(["type": "restore_done"]) == .restoreDone)
        #expect(Backup.Message(["type": "restore_failed"]) == .restoreFailed)
        #expect(Backup.state(["backups": [], "backup_in_progress": false, "restore_supported": false]).canRestore == false)
    }

    @Test func mergesSettingsLikeOctoPrint() {
        let settings: JSONValue = ["serial": ["autoconnect": false, "port": "/dev/ttyACM0"], "webcam": ["streamUrl": "/webcam/"]]
        let merged = settings.merging(["serial": ["autoconnect": true]])
        #expect(merged.value(at: "serial", "autoconnect")?.boolValue == true)
        #expect(merged.value(at: "serial", "port")?.stringValue == "/dev/ttyACM0")
        #expect(merged.value(at: "webcam", "streamUrl")?.stringValue == "/webcam/")
    }
}

struct HousekeepingTests {
    @Test func readsFileCheckResults() {
        let results = FileCheck.results(["check_result": ["local:prints/benchy.gcode": ["leaked_api_key"], "local:ok.gcode": [],
                                                          "sdcard:other.gco": ["travel_speed"]]])
        #expect(results == ["prints/benchy.gcode": ["leaked_api_key"]])
        #expect(FileCheck.Message(["action": "notify", "storage": "local", "path": "a.gcode", "types": ["travel_speed"]])
            == .found(storage: "local", path: "a.gcode", problems: ["travel_speed"]))
        #expect(FileCheck.Message(["action": "check_update"]) == .updated)
        #expect(FileCheck.helpURL(for: "leaked_api_key")?.absoluteString == "https://faq.octoprint.org/file-check-leaked-api-key")
    }

    @Test func readsLoggingSetup() {
        let setup = LoggingSetup(["setup": ["loggers": ["octoprint.server", "octoprint.util.comm"], "levels": ["octoprint.util.comm": "DEBUG"]],
                                  "serial_log": ["enabled": true]])
        #expect(setup.available == ["octoprint.server", "octoprint.util.comm"])
        #expect(setup.levels == ["octoprint.util.comm": "DEBUG"])
        #expect(setup.serialLog)
    }

    @Test func readsPluginLeftovers() {
        let leftovers = PluginLeftovers.list(["orphan_data": ["octolapse": ["settings": true, "data": false, "disabled": false]]])
        #expect(leftovers == [PluginLeftovers(key: "octolapse", settings: true, data: false)])
    }

    @Test func readsAddressChecks() {
        let check = AddressCheck(["url": "http://127.0.0.1:8080/?action=snapshot", "status": 200, "result": true,
                                  "response": ["assumed_content_type": "image/jpeg", "content": "/9j/"]])
        #expect(check.ok && check.status == 200 && check.contentType == "image/jpeg")
        #expect(check.content == Data([0xFF, 0xD8, 0xFF]))
    }

    @Test func knowsOctoPrintTwosStorageName() throws {
        let entry = try JSONDecoder().decode(FileEntry.self, from: Data(#"{"name": "a.gco", "origin": "printer"}"#.utf8))
        #expect(entry.origin == .printer && entry.origin.isOnPrinter)
        #expect(!FileOrigin.local.isOnPrinter)
    }
}
