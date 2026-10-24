import Foundation
import Observation
import SwiftUI

/// Owns the list of configured instances and a live `PrinterSession` for each.
@MainActor
@Observable
final class InstanceStore {
    private(set) var instances: [Instance] = []
    private(set) var sessions: [UUID: PrinterSession] = [:]

    /// Demo mode shows canned printers and never touches the network, stored keys or saved settings.
    /// Start in it with `--demo`, or switch at any time from the Help menu.
    private(set) var isDemo = CommandLine.arguments.contains("--demo")

    private let defaults = UserDefaults.standard
    private let storageKey = "instances.v1"

    init() {
        if isDemo {
            loadDemo()
            return
        }
        load()
        CredentialStore.migrateFromKeychain(ids: instances.map(\.id))
        for instance in instances { startSession(for: instance) }
    }

    /// Disconnects from your printers (they stay saved) and shows the demo printers instead.
    func enterDemo() {
        guard !isDemo else { return }
        stopAll()
        isDemo = true
        loadDemo()
    }

    /// Leaves demo mode and reconnects to your saved printers.
    func exitDemo() {
        guard isDemo else { return }
        stopAll()
        isDemo = false
        load()
        for instance in instances { startSession(for: instance) }
    }

    private func stopAll() {
        for session in sessions.values { session.stop() }
        sessions = [:]
        instances = []
    }

    /// Your own saved printers' IDs, even while demo mode is showing pretend ones.
    var savedInstanceIDs: [UUID] {
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Instance].self, from: data) else { return [] }
        return saved.map(\.id)
    }

    func session(for id: UUID?) -> PrinterSession? {
        id.flatMap { sessions[$0] }
    }

    func filament(for instance: Instance) -> Color {
        instance.filamentHex.flatMap(Color.init(hexString:)) ?? Palette.filaments[0]
    }

    func add(_ instance: Instance, apiKey: String?, access: ProxyAccess? = nil) {
        var instance = instance
        if instance.filamentHex == nil { instance.filamentHex = suggestedFilamentHex() }
        CredentialStore.setAPIKey(apiKey, for: instance.id)
        CredentialStore.setProxyAccess(access, for: instance.id)
        instances.append(instance)
        save()
        startSession(for: instance)
    }

    /// Saves changes to a printer and reconnects. Leaving `access` out keeps its proxy sign-in as it is.
    func update(_ instance: Instance, apiKey: String?, access: ProxyAccess?? = .none) {
        guard let index = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        CredentialStore.setAPIKey(apiKey, for: instance.id)
        if case .some(let access) = access { CredentialStore.setProxyAccess(access, for: instance.id) }
        instances[index] = instance
        save()
        sessions[instance.id]?.stop()
        startSession(for: instance)
    }

    /// Remembers a printer's self-signed certificate and reconnects with it.
    func trustCertificate(_ fingerprint: String, for id: UUID) {
        guard var instance = instances.first(where: { $0.id == id }) else { return }
        instance.trustedCertificate = fingerprint
        update(instance, apiKey: CredentialStore.apiKey(for: id))
    }

    func remove(_ id: UUID) {
        sessions[id]?.stop()
        sessions[id] = nil
        instances.removeAll { $0.id == id }
        CredentialStore.remove(id)
        PrintLog.remove(for: id)
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        instances.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func startSession(for instance: Instance) {
        let session = PrinterSession(instance: instance, apiKey: CredentialStore.apiKey(for: instance.id),
                                     access: CredentialStore.proxyAccess(for: instance.id))
        sessions[instance.id] = session
        session.start()
    }

    /// The first identity colour not already used by another printer.
    func suggestedFilamentHex() -> String? {
        let used = Set(instances.compactMap(\.filamentHex))
        let all = Palette.filaments.compactMap(\.hexString)
        return all.first { !used.contains($0) } ?? all[instances.count % all.count]
    }

    private func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Instance].self, from: data)
        {
            instances = decoded
        }
        // On first launch there are no printers; the window invites you to add one.
        // Give older/seeded entries an identity colour.
        for index in instances.indices where instances[index].filamentHex == nil {
            instances[index].filamentHex = suggestedFilamentHex()
        }
        save()
    }

    private func save() {
        guard !isDemo else { return }
        if let data = try? JSONEncoder().encode(instances) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func loadDemo() {
        let scenarios: [(String, String, PrinterSession.DemoScenario)] = [
            ("Workshop MK3S", "http://octopi-workshop.local/", .printing),
            ("Studio Ender", "http://octopi-studio.local/", .ready),
            ("Lab XL", "http://octopi-lab.local/", .toolchanger),
            ("Garage Voron", "http://voron.local/", .locked),
        ]
        for (index, (name, url, scenario)) in scenarios.enumerated() {
            let instance = Instance(name: name, baseURL: URL(string: url)!, filamentHex: Palette.filaments[index].hexString)
            instances.append(instance)
            let session = PrinterSession(instance: instance, apiKey: scenario == .locked ? nil : "demo")
            session.loadDemo(scenario)
            sessions[instance.id] = session
        }
    }
}
