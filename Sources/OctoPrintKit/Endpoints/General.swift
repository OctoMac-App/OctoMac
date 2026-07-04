import Foundation

// General information, auth and connection handling.
// https://docs.octoprint.org/en/main/api/general.html
// https://docs.octoprint.org/en/main/api/version.html
// https://docs.octoprint.org/en/main/api/server.html
// https://docs.octoprint.org/en/main/api/connection.html

extension OctoPrintClient {
    public func version() async throws -> VersionInfo {
        try await get("api/version")
    }

    public func server() async throws -> ServerInfo {
        try await get("api/server")
    }

    public func currentUser() async throws -> UserRecord {
        try await get("api/currentuser")
    }

    /// Passive login using the API key. Returns the user name + session needed to authenticate the push socket.
    public func passiveLogin() async throws -> UserRecord {
        try await post("api/login", body: ["passive": true] as CommandBody)
    }

    public func logout() async throws {
        try await post("api/logout", body: CommandBody())
    }

    // MARK: Connection

    public func connection() async throws -> ConnectionInfo {
        try await get("api/connection")
    }

    public func connect(_ request: ConnectRequest = .init()) async throws {
        try await post("api/connection", body: request.body)
    }

    public func disconnect() async throws {
        try await post("api/connection", body: ["command": "disconnect"] as CommandBody)
    }

    public func fakeAck() async throws {
        try await post("api/connection", body: ["command": "fake_ack"] as CommandBody)
    }
}
