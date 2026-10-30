import Foundation
import OctoPrintKit

/// A backup being restored, with OctoPrint's log as it goes.
struct BackupRestore: Equatable {
    enum Outcome: Equatable {
        case done
        case failed(String)
    }

    var name: String
    /// How much of a backup from this Mac has been sent, until OctoPrint starts restoring it.
    var upload: Double?
    var log: [String] = []
    var outcome: Outcome?

    var isRunning: Bool { outcome == nil }
}

/// The classic webcam's settings: where its stream and snapshots are, and which way up it is. On OctoPrint 1.9 and
/// later they belong to the Classic Webcam plugin; before that, to OctoPrint itself.
struct CameraSettings: Equatable {
    var stream = ""
    var snapshot = ""
    var flipH = false
    var flipV = false
    var rotate90 = false
    /// False on older OctoPrint, which keeps these under `webcam` with different names.
    var classicPlugin = true
    /// Neither place has a stream: the camera comes from another plugin, set up in OctoPrint.
    var fromOtherPlugin = false

    init() {}

    init(_ settings: JSONValue?) {
        if let plugin = settings?.value(at: "plugins", "classicwebcam"), plugin.objectValue != nil {
            stream = plugin["stream"]?.stringValue ?? ""
            snapshot = plugin["snapshot"]?.stringValue ?? ""
            flipH = plugin["flipH"]?.boolValue ?? false
            flipV = plugin["flipV"]?.boolValue ?? false
            rotate90 = plugin["rotate90"]?.boolValue ?? false
        } else if let webcam = settings?["webcam"], webcam["streamUrl"] != nil {
            classicPlugin = false
            stream = webcam["streamUrl"]?.stringValue ?? ""
            snapshot = webcam["snapshotUrl"]?.stringValue ?? ""
            flipH = webcam["flipH"]?.boolValue ?? false
            flipV = webcam["flipV"]?.boolValue ?? false
            rotate90 = webcam["rotate90"]?.boolValue ?? false
        } else {
            fromOtherPlugin = true
        }
    }

    /// What to send to OctoPrint's settings to save these.
    var partial: JSONValue {
        let trimmedStream = stream.trimmingCharacters(in: .whitespaces)
        let trimmedSnapshot = snapshot.trimmingCharacters(in: .whitespaces)
        if classicPlugin {
            return ["plugins": ["classicwebcam": [
                "stream": .string(trimmedStream), "snapshot": .string(trimmedSnapshot),
                "flipH": .bool(flipH), "flipV": .bool(flipV), "rotate90": .bool(rotate90),
            ]]]
        }
        return ["webcam": [
            "streamUrl": .string(trimmedStream), "snapshotUrl": .string(trimmedSnapshot),
            "flipH": .bool(flipH), "flipV": .bool(flipV), "rotate90": .bool(rotate90),
        ]]
    }
}

/// One of OctoPrint's temperature presets, being edited. Anything else OctoPrint keeps with it (a chamber
/// temperature) is kept as it was.
struct TemperaturePresetDraft: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var extruder: Double
    var bed: Double
    var other: [String: JSONValue] = [:]

    init(name: String, extruder: Double, bed: Double) {
        self.name = name
        self.extruder = extruder
        self.bed = bed
    }

    init(_ json: JSONValue) {
        var other = json.objectValue ?? [:]
        name = other.removeValue(forKey: "name")?.stringValue ?? ""
        extruder = other.removeValue(forKey: "extruder")?.doubleValue ?? 0
        bed = other.removeValue(forKey: "bed")?.doubleValue ?? 0
        self.other = other
    }

    var json: JSONValue {
        var object = other
        object["name"] = .string(name.trimmingCharacters(in: .whitespaces))
        object["extruder"] = .number(extruder.rounded())
        object["bed"] = .number(bed.rounded())
        return .object(object)
    }
}

/// The parts of a printer profile people usually change. Everything else stays as OctoPrint has it.
struct PrinterProfileDraft: Equatable {
    /// Nil for a new profile.
    var id: String?
    var name: String
    var model: String
    var width: Double
    var depth: Double
    var height: Double
    var round: Bool
    var originCentre: Bool
    var heatedBed: Bool
    var heatedChamber: Bool
    var nozzle: Double
    var extruders: Int
    var sharedNozzle: Bool

    init(_ profile: PrinterProfile?, asNew: Bool = false) {
        id = asNew ? nil : profile?.id
        name = asNew ? "" : profile?.name ?? ""
        model = profile?.model ?? ""
        width = profile?.volume?.width ?? 200
        depth = profile?.volume?.depth ?? 200
        height = profile?.volume?.height ?? 200
        round = profile?.volume?.formFactor == "circular"
        originCentre = profile?.volume?.origin == "center"
        heatedBed = profile?.heatedBed ?? true
        heatedChamber = profile?.heatedChamber ?? false
        nozzle = profile?.extruder?.nozzleDiameter ?? 0.4
        extruders = profile?.extruder?.count ?? 1
        sharedNozzle = profile?.extruder?.sharedNozzle ?? false
    }

    var json: JSONValue {
        var profile: [String: JSONValue] = [
            "name": .string(name.trimmingCharacters(in: .whitespaces)),
            "model": .string(model.trimmingCharacters(in: .whitespaces)),
            "heatedBed": .bool(heatedBed),
            "heatedChamber": .bool(heatedChamber),
            "volume": [
                "width": .number(width), "depth": .number(depth), "height": .number(height),
                "formFactor": .string(round ? "circular" : "rectangular"),
                "origin": .string(originCentre ? "center" : "lowerleft"),
            ],
            "extruder": ["nozzleDiameter": .number(nozzle), "count": .number(Double(extruders)), "sharedNozzle": .bool(sharedNozzle)],
        ]
        // OctoPrint needs an id for a new profile: the name, as it would make one itself.
        if id == nil { profile["id"] = .string(Self.identifier(from: name)) }
        return .object(profile)
    }

    /// "Ender 3 V3" becomes "ender_3_v3".
    static func identifier(from name: String) -> String {
        let lowered = name.trimmingCharacters(in: .whitespaces).lowercased(with: Locale(identifier: "en_US_POSIX"))
        let allowed = lowered.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return allowed.isEmpty ? "profile" : allowed
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && width > 0 && depth > 0 && height > 0 && nozzle > 0 && extruders >= 1
    }
}

extension HealthCheck.Item {
    /// What the check found, in plain words.
    var summary: String {
        switch key {
        case "filesystem_storage":
            let fullest = (context.objectValue ?? [:]).compactMap { $0.value.doubleValue }.max() ?? 0
            return String(localized: "The Raspberry Pi's storage is \(Fmt.percent(fullest)) full. Delete old prints, timelapses or backups to make room.")
        case "octoprint_freshness":
            let version = context["version"]?.stringValue ?? ""
            let latest = context["latest"]?.arrayValue?.last?.stringValue ?? ""
            return String(localized: "OctoPrint \(version) is several versions behind \(latest). Update it in the Software panel.")
        case "python_eol":
            let version = context["version"]?.stringValue ?? ""
            let date = (context["date"]?.stringValue).flatMap { try? Date($0, strategy: .iso8601.year().month().day()) }
                .map { $0.formatted(date: .long, time: .omitted) } ?? ""
            return context["soon"]?.boolValue == true
                ? String(localized: "Python \(version), which OctoPrint runs on, stops getting fixes on \(date). Newer OctoPrint versions will need a newer Python, which usually means setting up OctoPi again.")
                : String(localized: "Python \(version), which OctoPrint runs on, stopped getting fixes on \(date). Newer OctoPrint versions need a newer Python, which usually means setting up OctoPi again.")
        default:
            return String(localized: "OctoPrint's health check “\(key)” found something. OctoPrint's web page has the details.")
        }
    }
}
