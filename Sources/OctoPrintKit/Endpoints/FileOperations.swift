import Foundation

// File operations.
// https://docs.octoprint.org/en/main/api/files.html

extension OctoPrintClient {
    public func files(recursive: Bool = true, force: Bool = false) async throws -> FileList {
        var query = [URLQueryItem(name: "recursive", value: recursive ? "true" : "false")]
        if force { query.append(URLQueryItem(name: "force", value: "true")) }
        return try await get("api/files", query: query)
    }

    public func files(in origin: FileOrigin, recursive: Bool = true) async throws -> FileList {
        try await get("api/files/\(origin.rawValue)", query: [URLQueryItem(name: "recursive", value: recursive ? "true" : "false")])
    }

    public func file(_ path: String, origin: FileOrigin = .local) async throws -> FileEntry {
        try await get("api/files/\(origin.rawValue)/\(path)")
    }

    /// Uploads a file (G-code or model) to `origin`, optionally into `folder`, optionally selecting/printing it.
    @discardableResult
    public func upload(
        fileURL: URL,
        to origin: FileOrigin = .local,
        folder: String? = nil,
        select: Bool = false,
        print: Bool = false
    ) async throws -> UploadResponse {
        let data = try Data(contentsOf: fileURL)
        return try await upload(data: data, filename: fileURL.lastPathComponent, to: origin, folder: folder, select: select, print: print)
    }

    @discardableResult
    public func upload(
        data: Data,
        filename: String,
        to origin: FileOrigin = .local,
        folder: String? = nil,
        select: Bool = false,
        print: Bool = false
    ) async throws -> UploadResponse {
        var form = MultipartForm()
        form.addFile(name: "file", filename: filename, contentType: "application/octet-stream", data: data)
        if let folder, !folder.isEmpty { form.addField(name: "path", value: folder) }
        if select { form.addField(name: "select", value: "true") }
        if print { form.addField(name: "print", value: "true") }
        let request = makeRequest(.post, "api/files/\(origin.rawValue)", body: form.encoded(), contentType: form.contentType)
        let (responseData, _) = try await send(request)
        return (try? Self.decoder.decode(UploadResponse.self, from: responseData)) ?? UploadResponse()
    }

    public func createFolder(_ name: String, in parent: String? = nil, origin: FileOrigin = .local) async throws {
        var form = MultipartForm()
        form.addField(name: "foldername", value: name)
        if let parent, !parent.isEmpty { form.addField(name: "path", value: parent) }
        try await send(makeRequest(.post, "api/files/\(origin.rawValue)", body: form.encoded(), contentType: form.contentType))
    }

    public func select(_ path: String, origin: FileOrigin = .local, print: Bool = false) async throws {
        try await post("api/files/\(origin.rawValue)/\(path)", body: ["command": "select", "print": .bool(print)] as CommandBody)
    }

    public func unselect() async throws {
        try await post("api/files/local", body: ["command": "unselect"] as CommandBody)
    }

    public func slice(_ path: String, origin: FileOrigin = .local, slicer: String, profile: String? = nil, destination: String? = nil, select: Bool = false, print: Bool = false) async throws {
        var body: CommandBody = ["command": "slice", "slicer": .string(slicer), "select": .bool(select), "print": .bool(print)]
        if let profile { body["profile"] = .string(profile) }
        if let destination { body["gcode"] = .string(destination) }
        try await post("api/files/\(origin.rawValue)/\(path)", body: body)
    }

    public func copy(_ path: String, to destinationFolder: String, origin: FileOrigin = .local) async throws {
        try await post("api/files/\(origin.rawValue)/\(path)", body: ["command": "copy", "destination": .string(destinationFolder)] as CommandBody)
    }

    public func move(_ path: String, to destinationFolder: String, origin: FileOrigin = .local) async throws {
        try await post("api/files/\(origin.rawValue)/\(path)", body: ["command": "move", "destination": .string(destinationFolder)] as CommandBody)
    }

    public func deleteFile(_ path: String, origin: FileOrigin = .local) async throws {
        try await delete("api/files/\(origin.rawValue)/\(path)")
    }

    /// Downloads a file's contents (e.g. G-code for preview).
    public func download(_ entry: FileEntry) async throws -> Data {
        guard let ref = entry.refs?.download, let url = resolve(ref) else { throw OctoPrintError.invalidResponse }
        var request = URLRequest(url: url)
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key") }
        return try await send(request).0
    }
}

struct MultipartForm {
    let boundary = "OctoMac-\(UUID().uuidString)"
    private var parts: [Data] = []

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: String) {
        var part = Data()
        part.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        parts.append(part)
    }

    mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        var part = Data()
        let escaped = filename.replacingOccurrences(of: "\"", with: "_")
        part.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(escaped)\"\r\nContent-Type: \(contentType)\r\n\r\n")
        part.append(data)
        part.append("\r\n")
        parts.append(part)
    }

    func encoded() -> Data {
        var body = parts.reduce(into: Data()) { $0.append($1) }
        body.append("--\(boundary)--\r\n")
        return body
    }
}

extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
