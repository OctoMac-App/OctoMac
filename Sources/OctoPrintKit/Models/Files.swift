import Foundation

// https://docs.octoprint.org/en/main/api/datamodel.html#file-related

public enum FileOrigin: String, Codable, Sendable, CaseIterable {
    case local
    case sdcard
}

public struct GcodeAnalysis: Decodable, Sendable, Hashable {
    public struct Dimensions: Codable, Sendable, Hashable {
        public var width: Double?
        public var depth: Double?
        public var height: Double?
    }

    public var estimatedPrintTime: Double?
    public var filament: [String: FilamentUsage]
    public var dimensions: Dimensions?

    enum CodingKeys: String, CodingKey { case estimatedPrintTime, filament, dimensions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        estimatedPrintTime = try? c.decodeIfPresent(Double.self, forKey: .estimatedPrintTime)
        filament = decodeFilament(c, .filament)
        dimensions = try? c.decodeIfPresent(Dimensions.self, forKey: .dimensions)
    }

    public var totalFilamentLength: Double? {
        let lengths = filament.values.compactMap(\.length)
        return lengths.isEmpty ? nil : lengths.reduce(0, +)
    }
}

public struct FileRefs: Codable, Sendable, Hashable {
    public var resource: String?
    public var download: String?
    public var model: String?
}

public struct PrintHistory: Codable, Sendable, Hashable {
    public struct Last: Codable, Sendable, Hashable {
        public var date: Double?
        public var success: Bool?
        public var printTime: Double?
    }

    public var success: Int?
    public var failure: Int?
    public var last: Last?
}

public struct FileEntry: Decodable, Sendable, Hashable, Identifiable {
    public var name: String
    public var display: String?
    public var path: String
    /// `folder`, `machinecode` or `model`
    public var type: String?
    public var typePath: [String]?
    public var origin: FileOrigin
    public var size: Int?
    public var date: Date?
    public var children: [FileEntry]?
    public var gcodeAnalysis: GcodeAnalysis?
    public var refs: FileRefs?
    public var prints: PrintHistory?
    /// Relative URL of a preview image, provided by thumbnail plugins (e.g. PrusaSlicer Thumbnails, Cura Thumbnails).
    public var thumbnail: String?

    public var id: String { "\(origin.rawValue):\(path)" }
    public var displayName: String { display ?? name }
    public var isFolder: Bool { type == "folder" }
    public var isMachineCode: Bool { type == "machinecode" }
    public var isModel: Bool { type == "model" }

    enum CodingKeys: String, CodingKey {
        case name, display, path, type, typePath, origin, size, date, children, gcodeAnalysis, refs, prints, thumbnail
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        display = try? c.decodeIfPresent(String.self, forKey: .display)
        path = (try? c.decodeIfPresent(String.self, forKey: .path)) ?? name
        type = try? c.decodeIfPresent(String.self, forKey: .type)
        typePath = try? c.decodeIfPresent([String].self, forKey: .typePath)
        origin = (try? c.decodeIfPresent(FileOrigin.self, forKey: .origin)) ?? .local
        size = try? c.decodeIfPresent(Int.self, forKey: .size)
        date = (try? c.decodeIfPresent(Double.self, forKey: .date)).map(Date.init(timeIntervalSince1970:))
        // Folders always get a children array (possibly empty) so outline views show a disclosure triangle.
        let children = try c.decodeIfPresent([FileEntry].self, forKey: .children)
        self.children = children ?? (type == "folder" ? [] : nil)
        gcodeAnalysis = try? c.decodeIfPresent(GcodeAnalysis.self, forKey: .gcodeAnalysis)
        refs = try? c.decodeIfPresent(FileRefs.self, forKey: .refs)
        prints = try? c.decodeIfPresent(PrintHistory.self, forKey: .prints)
        thumbnail = (try? c.decodeIfPresent(String.self, forKey: .thumbnail)).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// `GET /api/files` and `GET /api/files/{location}`
public struct FileList: Decodable, Sendable {
    public var files: [FileEntry]
    public var free: Int?
    public var total: Int?
}

/// Response of an upload / folder creation.
public struct UploadResponse: Decodable, Sendable {
    public var done: Bool?
    public var effectiveSelect: Bool?
    public var effectivePrint: Bool?
}
