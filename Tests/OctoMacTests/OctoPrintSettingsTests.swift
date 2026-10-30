import Foundation
import Testing
@testable import OctoMac
@testable import OctoPrintKit

struct OctoPrintSettingsTests {
    @Test func namesCopiesBesideTheOriginal() {
        #expect(PrinterSession.copyName(for: "benchy.gcode", avoiding: []) == "benchy_copy.gcode")
        #expect(PrinterSession.copyName(for: "benchy.gcode", avoiding: ["benchy_copy.gcode"]) == "benchy_copy_2.gcode")
        #expect(PrinterSession.copyName(for: "notes", avoiding: []) == "notes_copy")
    }

    @Test func savesTheCameraWhereOctoPrintKeepsIt() {
        var modern = CameraSettings(["plugins": ["classicwebcam": ["stream": "/webcam/?action=stream", "flipH": true]]])
        #expect(modern.classicPlugin && modern.flipH && modern.stream == "/webcam/?action=stream")
        modern.rotate90 = true
        #expect(modern.partial.value(at: "plugins", "classicwebcam", "rotate90")?.boolValue == true)

        let old = CameraSettings(["webcam": ["streamUrl": "/webcam/?action=stream", "snapshotUrl": "http://127.0.0.1:8080/?action=snapshot"]])
        #expect(!old.classicPlugin)
        #expect(old.partial.value(at: "webcam", "snapshotUrl")?.stringValue == "http://127.0.0.1:8080/?action=snapshot")

        #expect(CameraSettings(["webcam": ["webcams": []]]).fromOtherPlugin)
    }

    @Test func keepsPresetDetailsItDoesntEdit() {
        var preset = TemperaturePresetDraft(["name": "ABS", "extruder": 240, "bed": 100, "chamber": 40])
        preset.bed = 105
        #expect(preset.json["chamber"]?.doubleValue == 40)
        #expect(preset.json["bed"]?.doubleValue == 105)
    }

    @Test func makesAProfileIdentifierFromItsName() {
        #expect(PrinterProfileDraft.identifier(from: "Ender 3 V3") == "ender_3_v3")
        #expect(PrinterProfileDraft.identifier(from: "  ") == "profile")
    }

    @Test func describesHealthChecks() {
        let storage = HealthCheck.Item(key: "filesystem_storage", result: .warning, context: ["uploads": 88.4, "logs": 3.1])
        #expect(storage.summary.contains("88"))
        #expect(HealthCheck.Item(key: "something_new", result: .issue).summary.contains("something_new"))
    }
}

struct RenameTests {
    @Test func keepsTheExtension() {
        #expect(PrinterSession.renamed("benchy.gcode", to: "boat", isFolder: false) == "boat.gcode")
        #expect(PrinterSession.renamed("benchy.gcode", to: "boat.GCODE", isFolder: false) == "boat.GCODE")
        #expect(PrinterSession.renamed("parts", to: " brackets ", isFolder: true) == "brackets")
    }
}

struct SlicedNameTests {
    @Test func readsTheSlicerDetailsOfACopy() {
        let original = SlicedName("6-piece-hook-set_0.2mm_PETG_MK3S_2h16m.gcode")
        #expect(original.title == "6-piece-hook-set" && original.tags == ["0.2mm", "PETG", "MK3S"])
        let copy = SlicedName("6-piece-hook-set_0.2mm_PETG_MK3S_2h16m_copy.gcode")
        #expect(copy.title == "6-piece-hook-set copy" && copy.tags == ["0.2mm", "PETG", "MK3S"])
        let second = SlicedName("6-piece-hook-set_0.2mm_PETG_MK3S_2h16m_copy_2.gcode")
        #expect(second.title == "6-piece-hook-set copy 2" && second.tags.count == 3)
        // Not a sliced name: left as it was.
        #expect(SlicedName("bracket_copy.gcode").title == "bracket copy")
    }
}
