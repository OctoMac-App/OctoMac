import Foundation
import Network
import Observation

/// Whether this Mac has a working network connection at all. Used to tell "the network is down" apart from
/// "macOS is blocking OctoMac from the local network", which look identical to the app otherwise.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var connected = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.connected = satisfied }
        }
        monitor.start(queue: .global(qos: .utility))
    }
}
