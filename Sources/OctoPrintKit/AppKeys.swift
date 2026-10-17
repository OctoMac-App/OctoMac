import Foundation

/// Obtains an API key via the bundled Application Keys plugin: the user approves the request in the
/// OctoPrint web UI and we receive a key, so nobody has to copy and paste anything.
/// https://docs.octoprint.org/en/main/bundledplugins/appkeys.html
public struct AppKeysAuthorizer: Sendable {
    public let baseURL: URL
    public let appName: String
    public let session: URLSession
    /// Headers for a reverse proxy in front of OctoPrint.
    public let headers: [String: String]

    public init(baseURL: URL, appName: String = "OctoMac", session: URLSession = .shared, headers: [String: String] = [:]) {
        self.baseURL = baseURL
        self.appName = appName
        self.session = session
        self.headers = headers
    }

    /// Requests a key for the server `client` talks to, through the same connection and proxy sign-in.
    public init(client: OctoPrintClient, appName: String = "OctoMac") {
        self.init(baseURL: client.baseURL, appName: appName, session: client.session, headers: client.headers)
    }

    private var client: OctoPrintClient { OctoPrintClient(baseURL: baseURL, apiKey: nil, session: session, headers: headers) }

    public func isSupported() async -> Bool {
        guard let (_, response) = try? await session.data(for: client.makeRequest(.get, "plugin/appkeys/probe")),
              let http = response as? HTTPURLResponse
        else { return false }
        return http.statusCode == 204
    }

    /// Like `isSupported`, but says why when a proxy in front of OctoPrint is in the way.
    private func checkSupported() async throws {
        let (data, response) = try await session.data(for: client.makeRequest(.get, "plugin/appkeys/probe"))
        guard let http = response as? HTTPURLResponse else { throw OctoPrintError.invalidResponse }
        if http.statusCode == 204 { return }
        if http.statusCode == 401, http.value(forHTTPHeaderField: "WWW-Authenticate")?.lowercased().hasPrefix("basic") == true {
            throw OctoPrintError.signInRequired
        }
        if String(decoding: data.prefix(256), as: UTF8.self).lowercased().contains("<html") { throw OctoPrintError.notOctoPrint }
        throw OctoPrintError.appKeysUnsupported
    }

    /// Starts a request and polls until the user decides.
    /// - Parameter openAuthDialog: called with the URL of the approval page (OctoPrint 1.8+), if provided by the server.
    public func requestKey(user: String? = nil, openAuthDialog: @Sendable (URL) async -> Void = { _ in }) async throws -> String {
        try await checkSupported()

        var body: CommandBody = ["app": .string(appName)]
        if let user, !user.isEmpty { body["user"] = .string(user) }
        let (data, response) = try await client.send(client.makeRequest(.post, "plugin/appkeys/request", body: OctoPrintClient.encoder.encode(body)))
        let json = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null

        guard let token = json["app_token"]?.stringValue else { throw OctoPrintError.invalidResponse }
        if let dialog = json["auth_dialog"]?.stringValue, let url = client.resolve(dialog) {
            await openAuthDialog(url)
        }

        let pollURL = response.value(forHTTPHeaderField: "Location").flatMap(client.resolve)
            ?? client.url("plugin/appkeys/request/\(token)")

        // The server discards requests that aren't polled at least every few seconds.
        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(1))
            var request = URLRequest(url: pollURL)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            client.authorize(&request)
            let (pollData, pollResponse) = try await session.data(for: request)
            guard let http = pollResponse as? HTTPURLResponse else { throw OctoPrintError.invalidResponse }
            switch http.statusCode {
            case 202:
                continue
            case 200:
                let result = try JSONDecoder().decode(JSONValue.self, from: pollData)
                guard let key = result["api_key"]?.stringValue else { throw OctoPrintError.invalidResponse }
                return key
            case 404:
                throw OctoPrintError.appKeyDenied
            default:
                throw OctoPrintError.http(status: http.statusCode, message: OctoPrintClient.errorMessage(from: pollData))
            }
        }
    }
}
