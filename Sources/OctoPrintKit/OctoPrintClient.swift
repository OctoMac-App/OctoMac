import Foundation

public enum OctoPrintError: LocalizedError, Sendable {
    case invalidResponse
    case http(status: Int, message: String?)
    case unauthorized(message: String?)
    case conflict(message: String?)
    case decoding(String)
    case appKeysUnsupported
    case appKeyDenied

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server returned an invalid response."
        case .http(let status, let message):
            message ?? "The server returned HTTP \(status)."
        case .unauthorized(let message):
            message ?? "Not authorised. Check the API key for this instance."
        case .conflict(let message):
            message ?? "The printer is not in a state that allows this (is it connected / idle?)."
        case .decoding(let detail):
            "Could not understand the server's response: \(detail)"
        case .appKeysUnsupported:
            "This OctoPrint instance doesn't support the Application Keys workflow. Paste an API key instead."
        case .appKeyDenied:
            "The access request was denied or timed out."
        }
    }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
}

/// Thin, stateless client for the OctoPrint REST API.
///
/// Docs: https://docs.octoprint.org/en/main/api/index.html
/// Endpoint groups live in `Endpoints/` as extensions on this type.
public struct OctoPrintClient: Sendable {
    public let baseURL: URL
    public let apiKey: String?
    public let session: URLSession

    public init(baseURL: URL, apiKey: String?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    public static let decoder = JSONDecoder()
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    // MARK: URL building

    public func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var url = baseURL.appending(path: trimmed, directoryHint: .notDirectory)
        if !query.isEmpty { url.append(queryItems: query) }
        return url
    }

    /// Resolves a URL that OctoPrint reports relative to itself (webcam streams, download refs, ...).
    public func resolve(_ string: String) -> URL? {
        if let absolute = URL(string: string), absolute.scheme != nil { return absolute }
        return URL(string: string, relativeTo: baseURL.hasDirectoryPath ? baseURL : baseURL.appending(path: ""))?.absoluteURL
    }

    public func makeRequest(_ method: HTTPMethod, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, contentType: String? = "application/json") -> URLRequest {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key") }
        if let body {
            request.httpBody = body
            if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        }
        return request
    }

    // MARK: Sending

    @discardableResult
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OctoPrintError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(from: data)
            switch http.statusCode {
            case 401, 403: throw OctoPrintError.unauthorized(message: message)
            case 409: throw OctoPrintError.conflict(message: message)
            default: throw OctoPrintError.http(status: http.statusCode, message: message)
            }
        }
        return (data, http)
    }

    public func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await send(makeRequest(.get, path, query: query))
        return try Self.decode(T.self, from: data)
    }

    public func post<T: Decodable>(_ path: String, body: some Encodable, as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await send(makeRequest(.post, path, body: Self.encoder.encode(body)))
        return try Self.decode(T.self, from: data)
    }

    /// Fire-and-forget command (most OctoPrint commands return `204 No Content`).
    public func post(_ path: String, body: some Encodable) async throws {
        try await send(makeRequest(.post, path, body: Self.encoder.encode(body)))
    }

    public func patch<T: Decodable>(_ path: String, body: some Encodable, as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await send(makeRequest(.patch, path, body: Self.encoder.encode(body)))
        return try Self.decode(T.self, from: data)
    }

    public func put<T: Decodable>(_ path: String, body: some Encodable, as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await send(makeRequest(.put, path, body: Self.encoder.encode(body)))
        return try Self.decode(T.self, from: data)
    }

    public func delete(_ path: String) async throws {
        try await send(makeRequest(.delete, path))
    }

    // MARK: Helpers

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw OctoPrintError.decoding(String(describing: error))
        }
    }

    static func errorMessage(from data: Data) -> String? {
        if let json = try? decoder.decode(JSONValue.self, from: data) {
            return json["error"]?.stringValue ?? json["message"]?.stringValue
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // OctoPrint/werkzeug errors are often HTML; don't surface markup to the user.
        return text.isEmpty || text.hasPrefix("<") ? nil : String(text.prefix(300))
    }
}

/// Body for the many `{"command": "..."}`-style endpoints.
public typealias CommandBody = [String: JSONValue]
