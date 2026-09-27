import Foundation
import Network
import Observation

/// Finds OctoPrint servers on the local network. OctoPrint announces itself over Bonjour as `_octoprint._tcp`,
/// with its web path in the TXT record.
@MainActor
@Observable
final class PrinterDiscovery {
    struct Found: Identifiable, Hashable {
        let name: String
        let endpoint: NWEndpoint
        let path: String
        let version: String?
        var id: String { name }

        /// `OctoPrint instance "Prusa MK3S+"` (or `OctoPrint instance on octopi`) shown as just `Prusa MK3S+`.
        var displayName: String {
            var text = name
            for prefix in ["OctoPrint instance on ", "OctoPrint instance "] where text.hasPrefix(prefix) {
                text.removeFirst(prefix.count)
            }
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            return text.isEmpty ? name : text
        }
    }

    private(set) var found: [Found] = []
    private(set) var searching = false
    @ObservationIgnored private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_octoprint._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let list = results.compactMap { result -> Found? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                var path = "/", version: String?
                if case .bonjour(let txt) = result.metadata {
                    path = txt["path"] ?? "/"
                    version = txt["version"]
                }
                return Found(name: name, endpoint: result.endpoint, path: path, version: version)
            }
            // A server on both Wi-Fi and Ethernet is listed once per interface.
            .reduce(into: [Found]()) { list, item in if !list.contains(where: { $0.name == item.name }) { list.append(item) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            Task { @MainActor in self?.found = list }
        }
        browser.stateUpdateHandler = { [weak self] state in
            let active: Bool
            switch state {
            case .ready, .setup: active = true
            default: active = false
            }
            Task { @MainActor in self?.searching = active }
        }
        browser.start(queue: .main)
        self.browser = browser
        searching = true
    }

    func stop() {
        browser?.cancel()
        browser = nil
        searching = false
    }

    /// Works out a printer's address: connects to the advertised service and reads back the host and port.
    /// Prefers IPv4, which is what people recognise and type.
    static func address(of found: Found) async -> URL? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: found.endpoint, using: parameters)
        return await withCheckedContinuation { continuation in
            let once = Once()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var url: URL?
                    if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint {
                        var text = "\(host)"
                        if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }
                        if text.contains(":") { text = "[\(text)]" }
                        let portPart = port.rawValue == 80 ? "" : ":\(port.rawValue)"
                        let path = found.path.hasPrefix("/") ? found.path : "/" + found.path
                        url = URL(string: "http://\(text)\(portPart)\(path)")
                    }
                    connection.cancel()
                    if once.claim() { continuation.resume(returning: url) }
                case .failed, .cancelled:
                    if once.claim() { continuation.resume(returning: nil) }
                default:
                    break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 6) {
                connection.cancel()
                if once.claim() { continuation.resume(returning: nil) }
            }
        }
    }
}

/// Lets exactly one of several callbacks resume a continuation.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.withLock { defer { done = true }; return !done } }
}
