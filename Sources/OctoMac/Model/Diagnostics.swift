import AppKit
import Foundation
import OctoPrintKit
import UserNotifications

/// A plain-text summary for bug reports, written so it can be shared publicly on GitHub.
/// It describes the app, the Mac and each printer's setup, and deliberately leaves out anything personal:
/// printer names and addresses, API keys, user names, file names and error messages that might quote them.
@MainActor
enum Diagnostics {
    static let issuesURL = URL(string: "https://github.com/OctoMac-App/OctoMac/issues")!

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "development"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    /// Opens a new bug report on GitHub with the version filled in.
    static var newIssueURL: URL {
        var components = URLComponents(url: issuesURL.appending(path: "new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "version", value: appVersion),
        ]
        return components.url!
    }

    static func report(store: InstanceStore, notifications: UNAuthorizationStatus) -> String {
        report(printers: store.instances.map { ($0, store.sessions[$0.id]) }, isDemo: store.isDemo, notifications: notifications)
    }

    static func report(printers: [(Instance, PrinterSession?)], isDemo: Bool, notifications: UNAuthorizationStatus) -> String {
        var lines: [String] = []
        lines.append("OctoMac diagnostics")
        lines.append("Written \(Date.now.formatted(.iso8601))")
        lines.append("This file leaves out printer names and addresses, API keys, user names and file names.")
        lines.append("")
        lines.append("OctoMac \(appVersion)")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Mac \(sysctl("hw.model") ?? "unknown"), \(chip)")
        lines.append("Demo mode: \(isDemo ? "on" : "off")")
        lines.append("API keys kept in: \(CredentialStore.usesKeychain ? "Keychain" : "OctoMac's own file")")
        lines.append("Notifications: \(describe(notifications)); switched on: "
                     + NotificationKind.allCases.filter(\.isEnabled).map(\.rawValue).joined(separator: ", "))
        lines.append("Temperature unit: \(TemperatureUnit.current.rawValue)")

        for (index, (_, session)) in printers.enumerated() {
            lines.append("")
            lines.append("Printer \(index + 1)")
            guard let session else {
                lines.append("  No session")
                continue
            }
            lines.append("  Connection to OctoPrint: \(describe(session.link))")
            lines.append("  Printer connected: \(session.isPrinterConnected ? "yes" : "no")")
            if let state = session.state?.text { lines.append("  Printer state: \(state)") }
            if let version = session.version { lines.append("  OctoPrint \(version.server), API \(version.api)") }
            if let firmware = session.firmware { lines.append("  Firmware: \(firmware)") }
            if let profile = session.currentProfile {
                let volume = profile.volume.map { "\(Fmt.number($0.width)) x \(Fmt.number($0.depth)) x \(Fmt.number($0.height)) mm" } ?? "unknown size"
                lines.append("  Profile: \(profile.extruder?.count ?? 1) extruder(s), shared nozzle \(profile.extruder?.sharedNozzle == true ? "yes" : "no"), heated bed \(profile.heatedBed == true ? "yes" : "no"), \(volume)")
            }
            if let pi = session.pi {
                lines.append("  Raspberry Pi: \(pi.model ?? "unknown model"), OctoPi \(pi.octoPiVersion ?? "unknown")")
            }
            if let throttle = session.throttle {
                lines.append("  Pi power or heat problem: now \(throttle.currentIssue ? "yes" : "no"), since start \(throttle.pastIssue ? "yes" : "no")")
            }
            if let error = session.printerError, !error.isEmpty {
                lines.append("  Last connection error type: \(error.reason.isEmpty ? "unknown" : error.reason)")
            }
            let plugins = (session.settings?["plugins"]?.objectValue?.keys).map { Array($0).sorted() } ?? []
            lines.append("  Plugins with settings: \(plugins.isEmpty ? "none reported" : plugins.joined(separator: ", "))")
            lines.append("  Webcam configured: \(session.webcamStreamURL == nil ? "no" : "yes")")
            lines.append("  Files: \(session.files.count) at the top level")
        }
        if printers.isEmpty { lines.append(""); lines.append("No printers added.") }
        return lines.joined(separator: "\n") + "\n"
    }

    private static var chip: String {
        #if arch(arm64)
        "Apple silicon"
        #else
        ProcessInfo.processInfo.isTranslated ? "Apple silicon (running as Intel)" : "Intel"
        #endif
    }

    private static func describe(_ link: PrinterSession.Link) -> String {
        switch link {
        case .needsAPIKey: "needs an API key"
        case .connecting: "connecting"
        case .online: "online"
        // The offline reason can quote the address, so it's left out.
        case .offline: "offline"
        }
    }

    private static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral: "allowed"
        case .denied: "turned off in System Settings"
        case .notDetermined: "not asked yet"
        @unknown default: "unknown"
        }
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

extension ProcessInfo {
    /// True for an Intel build running under Rosetta.
    var isTranslated: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &value, &size, nil, 0) == 0 && value == 1
    }
}
