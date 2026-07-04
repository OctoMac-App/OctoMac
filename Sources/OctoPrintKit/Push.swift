import Foundation

// Push updates over OctoPrint's SockJS endpoint (raw websocket transport).
// https://docs.octoprint.org/en/main/api/push.html

/// Payload of `current` and `history` messages.
public struct CurrentPayload: Decodable, Sendable {
    public var state: PrinterState?
    public var job: JobInfo?
    public var progress: JobProgress?
    public var currentZ: Double?
    public var offsets: [String: Double]?
    public var temps: [TemperatureSnapshot]
    public var logs: [String]
    public var messages: [String]
    public var busyFiles: [JSONValue]?
    public var serverTime: Double?

    enum CodingKeys: String, CodingKey {
        case state, job, progress, currentZ, offsets, temps, logs, messages, busyFiles, serverTime
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try? c.decodeIfPresent(PrinterState.self, forKey: .state)
        job = try? c.decodeIfPresent(JobInfo.self, forKey: .job)
        progress = try? c.decodeIfPresent(JobProgress.self, forKey: .progress)
        currentZ = try? c.decodeIfPresent(Double.self, forKey: .currentZ)
        offsets = try? c.decodeIfPresent([String: Double].self, forKey: .offsets)
        temps = (try? c.decodeIfPresent([TemperatureSnapshot].self, forKey: .temps)) ?? []
        logs = (try? c.decodeIfPresent([String].self, forKey: .logs)) ?? []
        messages = (try? c.decodeIfPresent([String].self, forKey: .messages)) ?? []
        busyFiles = try? c.decodeIfPresent([JSONValue].self, forKey: .busyFiles)
        serverTime = try? c.decodeIfPresent(Double.self, forKey: .serverTime)
    }
}

public struct ServerEvent: Sendable {
    /// e.g. `PrintStarted`, `FileAdded`, `Connected`. See https://docs.octoprint.org/en/main/events/index.html
    public var type: String
    public var payload: JSONValue
}

public enum PushMessage: Sendable {
    case connected(JSONValue)
    case reauthRequired(reason: String?)
    case current(CurrentPayload)
    case history(CurrentPayload)
    case event(ServerEvent)
    case slicingProgress(JSONValue)
    case plugin(id: String, data: JSONValue)
    case timelapse(JSONValue)
    case other(type: String, payload: JSONValue)

    /// Parses one websocket frame. OctoPrint frames are `{"<type>": <payload>}`.
    public static func parse(_ data: Data) throws -> [PushMessage] {
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let object = json.objectValue else { return [] }
        return object.map { type, payload in
            switch type {
            case "connected":
                return .connected(payload)
            case "reauthRequired":
                return .reauthRequired(reason: payload["reason"]?.stringValue)
            case "current":
                if let value = try? payload.decode(CurrentPayload.self) { return .current(value) }
            case "history":
                if let value = try? payload.decode(CurrentPayload.self) { return .history(value) }
            case "event":
                return .event(ServerEvent(type: payload["type"]?.stringValue ?? "", payload: payload["payload"] ?? .null))
            case "slicingProgress":
                return .slicingProgress(payload)
            case "plugin":
                return .plugin(id: payload["plugin"]?.stringValue ?? "", data: payload["data"] ?? .null)
            case "timelapse":
                return .timelapse(payload)
            default:
                break
            }
            return .other(type: type, payload: payload)
        }
    }
}

public enum PushEvent: Sendable {
    case connecting
    case connected(user: String?)
    case disconnected(String?)
    case message(PushMessage)
}

/// Maintains a websocket to an OctoPrint instance, authenticating with the client's API key and
/// reconnecting with backoff. Consume `events`; call `stop()` when done.
public actor PushClient {
    public nonisolated let events: AsyncStream<PushEvent>
    private let continuation: AsyncStream<PushEvent>.Continuation
    private let client: OctoPrintClient
    private let throttle: Int
    private var loop: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?

    /// - Parameter throttle: multiplier on OctoPrint's 500ms `current` push interval (1 = every 0.5s).
    public init(client: OctoPrintClient, throttle: Int = 1) {
        self.client = client
        self.throttle = throttle
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
    }

    public var websocketURL: URL {
        var components = URLComponents(url: client.url("sockjs/websocket"), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        return components.url!
    }

    public func start() {
        guard loop == nil else { return }
        loop = Task { await self.run() }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        continuation.yield(.disconnected(nil))
    }

    public func finish() {
        stop()
        continuation.finish()
    }

    /// Send a raw message, e.g. `["throttle": 2]`.
    public func send(_ message: JSONValue) async throws {
        let data = try JSONEncoder().encode(message)
        try await socket?.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func run() async {
        var delay: Duration = .seconds(1)
        while !Task.isCancelled {
            do {
                try await runOnce()
                delay = .seconds(1)
            } catch {
                if Task.isCancelled { break }
                continuation.yield(.disconnected(error.localizedDescription))
            }
            if Task.isCancelled { break }
            try? await Task.sleep(for: delay)
            delay = min(delay * 2, .seconds(30))
        }
    }

    private func runOnce() async throws {
        continuation.yield(.connecting)
        let login = try await client.passiveLogin()

        var request = URLRequest(url: websocketURL)
        if let apiKey = client.apiKey { request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key") }
        let socket = client.session.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        while !Task.isCancelled {
            let frame = try await socket.receive()
            let data: Data
            switch frame {
            case .data(let value): data = value
            case .string(let value): data = Data(value.utf8)
            @unknown default: continue
            }
            for message in (try? PushMessage.parse(data)) ?? [] {
                switch message {
                case .connected:
                    if let name = login.name, let session = login.session {
                        try await send(["auth": .string("\(name):\(session)")])
                    }
                    if throttle > 1 { try await send(["throttle": JSONValue(throttle)]) }
                    continuation.yield(.connected(user: login.name))
                case .reauthRequired(let reason):
                    throw OctoPrintError.unauthorized(message: "Session expired (\(reason ?? "unknown")), reconnecting.")
                default:
                    break
                }
                continuation.yield(.message(message))
            }
        }
    }
}
