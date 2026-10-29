import AppKit
import Foundation

/// The languages OctoMac is translated into, and the choice of which to use. By default OctoMac follows macOS, and
/// falls back to UK English for languages it doesn't have. Choosing one here applies after OctoMac restarts.
enum AppLanguage {
    /// Language codes, with each language's name in that language.
    static let available: [(code: String, name: String)] = [
        ("en-GB", "English (UK)"),
        ("en", "English (US)"),
        ("cs", "Čeština"),
        ("cy", "Cymraeg"),
        ("da", "Dansk"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("fr", "Français"),
        ("it", "Italiano"),
        ("nl", "Nederlands"),
        ("nb", "Norsk bokmål"),
        ("pl", "Polski"),
        ("pt-PT", "Português"),
        ("fi", "Suomi"),
        ("sv", "Svenska"),
    ]

    private static let key = "AppleLanguages"

    /// The language chosen in Settings, or nil to follow macOS. Read from OctoMac's own preferences only, not the
    /// system-wide list.
    static var chosen: String? {
        get { UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key].flatMap { ($0 as? [String])?.first } }
        set {
            if let newValue { UserDefaults.standard.set([newValue], forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    /// The language OctoMac is showing now.
    static var current: String { Bundle.main.preferredLocalizations.first ?? "en-GB" }

    static func name(of code: String) -> String {
        available.first { $0.code == code }?.name ?? code
    }

    /// Opens a fresh copy of OctoMac, then quits this one, so a new language takes effect.
    @MainActor
    static func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
