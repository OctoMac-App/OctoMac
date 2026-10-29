import AppKit
import Foundation
import UniformTypeIdentifiers

/// The printer list as a file, for moving to another Mac: names, addresses, colours and trusted certificates.
/// API keys and proxy sign-ins are never included, so the file is safe to email or keep in the cloud; each printer
/// asks to be approved again on the new Mac.
struct PrinterList: Codable, Equatable {
    struct Printer: Codable, Equatable {
        var name: String
        var address: URL
        var colour: String?
        var pushThrottle: Int?
        /// The fingerprint of a self-signed certificate you chose to trust. Not a secret.
        var trustedCertificate: String?
    }

    var app = "OctoMac"
    var version = 1
    var printers: [Printer]

    init(_ instances: [Instance]) {
        printers = instances.map {
            Printer(name: $0.name, address: $0.baseURL, colour: $0.filamentHex,
                    pushThrottle: $0.pushThrottle == 1 ? nil : $0.pushThrottle, trustedCertificate: $0.trustedCertificate)
        }
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func read(_ data: Data) throws -> PrinterList {
        let list = try JSONDecoder().decode(PrinterList.self, from: data)
        guard list.app == "OctoMac" else { throw CocoaError(.fileReadCorruptFile) }
        return list
    }

    /// The printers not already in `existing`, matched by address, as new printers with no keys yet.
    func newInstances(alongside existing: [Instance]) -> [Instance] {
        var known = Set(existing.map { Self.key($0.baseURL) })
        return printers.compactMap { printer in
            guard let url = Instance.normalisedURL(from: printer.address.absoluteString), known.insert(Self.key(url)).inserted else { return nil }
            return Instance(name: printer.name, baseURL: url, pushThrottle: max(printer.pushThrottle ?? 1, 1),
                            filamentHex: printer.colour, trustedCertificate: printer.trustedCertificate)
        }
    }

    private static func key(_ url: URL) -> String { url.absoluteString.lowercased() }
}

/// Export and import from Settings or the File menu.
@MainActor
enum PrinterTransfer {
    static func export(_ store: InstanceStore) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "OctoMac Printers") + ".json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PrinterList(store.instances).data().write(to: url, options: .atomic)
            let count = store.instances.count
            store.notice = .init(String(localized: "Exported \(count) printers. API keys aren't included."))
        } catch {
            store.notice = .init(String(localized: "Couldn't export the printers: \(error.localizedDescription)"), isProblem: true)
        }
    }

    static func importList(into store: InstanceStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let list = try PrinterList.read(Data(contentsOf: url))
            let added = list.newInstances(alongside: store.instances)
            for instance in added { store.add(instance, apiKey: nil) }
            let skipped = list.printers.count - added.count
            if added.isEmpty {
                store.notice = .init(String(localized: "Those printers are already in OctoMac."))
            } else if skipped > 0 {
                store.notice = .init(String(localized: "Added \(added.count) printers, and skipped \(skipped) already here. Approve each one in OctoPrint to connect."))
            } else {
                store.notice = .init(String(localized: "Added \(added.count) printers. Approve each one in OctoPrint to connect."))
            }
        } catch {
            store.notice = .init(String(localized: "That file isn't an OctoMac printer list."), isProblem: true)
        }
    }
}
