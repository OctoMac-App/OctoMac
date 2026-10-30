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

    /// Each language's flag: the same pictures as the website's language picker (`website/site/flags`, from the
    /// flag-icons project), bundled into the app's Resources/Flags.
    @MainActor
    static func flag(of code: String) -> NSImage? {
        let file: String? = switch code {
        case "en-GB": "gb"
        case "en": "us"
        case "cs": "cz"
        case "cy": "gb-wls"
        case "da": "dk"
        case "de": "de"
        case "es": "es"
        case "fr": "fr"
        case "it": "it"
        case "nl": "nl"
        case "nb": "no"
        case "pl": "pl"
        case "pt-PT": "pt"
        case "fi": "fi"
        case "sv": "se"
        default: nil
        }
        guard let file else { return nil }
        if let cached = flags[file] { return cached }
        let image = Bundle.main.url(forResource: file, withExtension: "svg", subdirectory: "Flags").flatMap(NSImage.init(contentsOf:))
        flags[file] = image
        return image
    }

    @MainActor private static var flags: [String: NSImage] = [:]

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
