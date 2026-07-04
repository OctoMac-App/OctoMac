import Foundation

// https://docs.octoprint.org/en/main/api/datamodel.html#job-related

public struct FilamentUsage: Codable, Sendable, Hashable {
    public var length: Double?
    public var volume: Double?
}

/// Decodes OctoPrint's filament block, which is `null`, a per-tool map, or (very old servers) a single usage.
func decodeFilament<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [String: FilamentUsage] {
    if let perTool = try? c.decodeIfPresent([String: FilamentUsage?].self, forKey: key) {
        return perTool.compactMapValues { $0 }
    }
    if let single = try? c.decodeIfPresent(FilamentUsage.self, forKey: key) {
        return ["tool0": single]
    }
    return [:]
}

public struct JobFile: Codable, Sendable, Hashable {
    public var name: String?
    public var path: String?
    public var display: String?
    public var origin: String?
    public var size: Int?
    public var date: Int?

    public var displayName: String? { display ?? name }
}

public struct JobInfo: Decodable, Sendable, Hashable {
    public var file: JobFile
    public var estimatedPrintTime: Double?
    public var lastPrintTime: Double?
    public var filament: [String: FilamentUsage]
    public var user: String?

    enum CodingKeys: String, CodingKey {
        case file, estimatedPrintTime, lastPrintTime, filament, user
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = (try? c.decodeIfPresent(JobFile.self, forKey: .file)) ?? JobFile()
        estimatedPrintTime = try? c.decodeIfPresent(Double.self, forKey: .estimatedPrintTime)
        lastPrintTime = try? c.decodeIfPresent(Double.self, forKey: .lastPrintTime)
        filament = decodeFilament(c, .filament)
        user = try? c.decodeIfPresent(String.self, forKey: .user)
    }

    public var hasFile: Bool { file.path != nil || file.name != nil }
}

public struct JobProgress: Codable, Sendable, Hashable {
    /// 0–100
    public var completion: Double?
    public var filepos: Int?
    /// Seconds
    public var printTime: Double?
    /// Seconds
    public var printTimeLeft: Double?
    /// linear, analysis, estimate, average, mixed-analysis, mixed-average
    public var printTimeLeftOrigin: String?

    public var fraction: Double? { completion.map { max(0, min(1, $0 / 100)) } }
}

/// `GET /api/job`
public struct JobStatus: Decodable, Sendable {
    public var job: JobInfo?
    public var progress: JobProgress?
    public var state: String?
    public var error: String?
}

public enum JobCommand: Sendable {
    case start
    case cancel
    case restart
    case pause
    case resume
    case togglePause

    var body: CommandBody {
        switch self {
        case .start: ["command": "start"]
        case .cancel: ["command": "cancel"]
        case .restart: ["command": "restart"]
        case .pause: ["command": "pause", "action": "pause"]
        case .resume: ["command": "pause", "action": "resume"]
        case .togglePause: ["command": "pause", "action": "toggle"]
        }
    }
}
