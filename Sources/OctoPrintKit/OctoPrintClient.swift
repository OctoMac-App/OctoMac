import Foundation

public enum OctoPrintError: LocalizedError, Sendable {
    case invalidResponse
    case http(status: Int, message: String?)
    case unauthorized(message: String?)
    case conflict(message: String?)
    case decoding(String)
    case appKeysUnsupported
    case appKeyDenied
    /// Something in front of OctoPrint (a reverse proxy) wants a user name and password.
    case signInRequired
    /// The address answered with a web page rather than OctoPrint's API, for example a sign-in page.
    case notOctoPrint

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "The server returned an invalid response.")
        case .http(let status, let message):
            message ?? String(localized: "The server returned HTTP \(status).")
        case .unauthorized(let message):
            message ?? String(localized: "Not authorised. Check the API key for this printer.")
        case .conflict(let message):
            message ?? String(localized: "The printer can't do that right now. Is it connected and idle?")
        case .decoding(let detail):
            String(localized: "Could not understand the server's response: \(detail)")
        case .appKeysUnsupported:
            String(localized: "This OctoPrint can't hand out access this way. Paste an API key instead.")
        case .appKeyDenied:
            String(localized: "The access request was denied or timed out.")
        case .signInRequired:
            String(localized: "This address asks for a user name and password before OctoPrint. Add them under Sign-in.")
        case .notOctoPrint:
            String(localized: "This address answered with a web page instead of OctoPrint, perhaps a sign-in page. Check the address, or add the headers it needs under Sign-in.")
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
    /// Extra headers for a reverse proxy in front of OctoPrint, such as `Authorization` for a user name and
    /// password, or Cloudflare Access service tokens.
    public let headers: [String: String]

    public init(baseURL: URL, apiKey: String?, session: URLSession = .shared, headers: [String: String] = [:]) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.headers = headers
    }

    /// The same server and sign-in, with a different API key.
    public func with(apiKey: String?) -> OctoPrintClient {
        OctoPrintClient(baseURL: baseURL, apiKey: apiKey, session: session, headers: headers)
    }

    /// Adds the API key and any proxy headers, but only for requests to this printer's own host, so they never
    /// reach a camera or other server elsewhere.
    public func authorize(_ request: inout URLRequest) {
        guard let host = request.url?.host(), host.caseInsensitiveCompare(baseURL.host() ?? "") == .orderedSame else { return }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let apiKey, !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key") }
    }

    /// An `Authorization` header value for HTTP basic authentication.
    public static func basicAuthorization(user: String, password: String) -> String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
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
        authorize(&request)
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
        try Self.check(http, data: data)
        return (data, http)
    }

    /// Uploads a request body, reporting how much has been sent (0–1) as it goes.
    @discardableResult
    public func upload(_ request: URLRequest, body: Data, progress: @escaping @Sendable (Double) -> Void) async throws -> (Data, HTTPURLResponse) {
        let delegate = UploadProgressDelegate(onProgress: progress)
        let (data, response) = try await session.upload(for: request, from: body, delegate: delegate)
        guard let http = response as? HTTPURLResponse else { throw OctoPrintError.invalidResponse }
        try Self.check(http, data: data)
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

    static func check(_ http: HTTPURLResponse, data: Data) throws {
        // OctoPrint itself never asks for basic authentication; a proxy in front of it does.
        if http.statusCode == 401, http.value(forHTTPHeaderField: "WWW-Authenticate")?.lowercased().hasPrefix("basic") == true {
            throw OctoPrintError.signInRequired
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = errorMessage(from: data)
            switch http.statusCode {
            case 401, 403: throw OctoPrintError.unauthorized(message: message)
            case 409: throw OctoPrintError.conflict(message: message)
            default: throw OctoPrintError.http(status: http.statusCode, message: message)
            }
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            // A sign-in page (Cloudflare Access, Authelia and the like) instead of OctoPrint's JSON.
            if data.prefix(256).contains(UInt8(ascii: "<")), String(decoding: data.prefix(256), as: UTF8.self).lowercased().contains("<html") {
                throw OctoPrintError.notOctoPrint
            }
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

final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
