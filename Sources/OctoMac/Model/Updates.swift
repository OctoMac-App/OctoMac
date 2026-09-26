import Foundation
import Observation
import Sparkle

/// Automatic updates with Sparkle. New versions are listed in `appcast.xml` in the repository and downloaded from
/// GitHub Releases; each one is signed with a key that lives only on the maintainer's Mac.
@MainActor
@Observable
final class Updates {
    static let shared = Updates()

    /// Nil when running without an app bundle (`swift run`), where there's nothing to update.
    private let controller: SPUStandardUpdaterController?
    private(set) var canCheck = false
    private var observation: NSKeyValueObservation?

    private init() {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        canCheck = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = value }
        }
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}
