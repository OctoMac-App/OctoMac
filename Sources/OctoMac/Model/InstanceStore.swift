import Foundation
import Observation
import SwiftUI

/// Owns the list of configured instances and a live `PrinterSession` for each.
@MainActor
@Observable
final class InstanceStore {
    private(set) var instances: [Instance] = []
    private(set) var sessions: [UUID: PrinterSession] = [:]

    /// `--demo` on the command line shows canned printers and never touches the network, stored keys or saved settings.
    let isDemo = CommandLine.arguments.contains("--demo")

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

    func session(for id: UUID?) -> PrinterSession? {
        id.flatMap { sessions[$0] }
    }

    func filament(for instance: Instance) -> Color {
        instance.filamentHex.flatMap(Color.init(hexString:)) ?? Palette.filaments[0]
    }

    func add(_ instance: Instance, apiKey: String?) {
        var instance = instance
        if instance.filamentHex == nil { instance.filamentHex = suggestedFilamentHex() }
        CredentialStore.setAPIKey(apiKey, for: instance.id)
        instances.append(instance)
        save()
        startSession(for: instance)
    }

    func update(_ instance: Instance, apiKey: String?) {
        guard let index = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        CredentialStore.setAPIKey(apiKey, for: instance.id)
        instances[index] = instance
        save()
        sessions[instance.id]?.stop()
        startSession(for: instance)
    }

    func remove(_ id: UUID) {
        sessions[id]?.stop()
        sessions[id] = nil
        instances.removeAll { $0.id == id }
        CredentialStore.setAPIKey(nil, for: id)
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        instances.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func startSession(for instance: Instance) {
        let session = PrinterSession(instance: instance, apiKey: CredentialStore.apiKey(for: instance.id))
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
        } else {
            // First launch: pre-populate the known servers; they still need authorising.
            instances = [
                Instance(name: "OctoPrint 1", baseURL: URL(string: "https://octoprint1.dir.to/")!),
                Instance(name: "OctoPrint 2", baseURL: URL(string: "https://octoprint2.dir.to/")!),
            ]
        }
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
            ("OctoPrint 1", "https://octoprint1.dir.to/", .printing),
            ("OctoPrint 2", "https://octoprint2.dir.to/", .ready),
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
