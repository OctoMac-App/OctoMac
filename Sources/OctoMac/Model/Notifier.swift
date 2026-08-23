import AppKit
import Foundation
import UserNotifications

/// The kinds of thing OctoMac can tell you about, each with its own switch in Settings.
enum NotificationKind: String, CaseIterable, Identifiable {
    case printDone, printFailed, needsAttention, printerProblem, piWarning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .printDone: "Print finished"
        case .printFailed: "Print failed or stopped"
        case .needsAttention: "Printer needs you"
        case .printerProblem: "Printer stopped answering"
        case .piWarning: "Raspberry Pi warnings"
        }
    }

    var detail: String {
        switch self {
        case .printDone: "When a print completes."
        case .printFailed: "When a print fails, or is stopped from the printer."
        case .needsAttention: "Filament changes, a paused print, or a filament choice for the Prusa MMU."
        case .printerProblem: "When the printer reports an error or drops its connection mid-print."
        case .piWarning: "Low power or overheating on the Raspberry Pi, which can spoil prints."
        }
    }

    var defaultsKey: String { "notify.\(rawValue)" }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }
}

/// Posts macOS notifications for printer events. Banners for the printer you're looking at are skipped while
/// OctoMac is in front, since you can already see what happened.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private var center: UNUserNotificationCenter? {
        // Notifications need a real app bundle; `swift run` builds don't have one.
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    private var asked = false
    /// Messages already sent recently, so a burst of identical events makes one banner.
    private var recent: [String: Date] = [:]

    /// Sets up delivery and, the first time OctoMac runs, asks for permission so notifications work from the start.
    /// After that, each kind can be switched off in Settings.
    func start() {
        guard let center else { return }
        center.delegate = self
        Task {
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = await requestPermission()
            }
        }
    }

    func post(_ kind: NotificationKind, printer: Instance, title: String, body: String) {
        guard kind.isEnabled, let center else { return }
        let key = "\(printer.id)|\(title)|\(body)"
        if let last = recent[key], Date.now.timeIntervalSince(last) < 60 { return }
        recent[key] = .now

        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = printer.name
        content.body = body
        content.sound = kind == .printDone ? .default : .defaultCritical
        content.threadIdentifier = printer.id.uuidString
        content.userInfo = ["printer": printer.id.uuidString]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        Task {
            if !asked {
                asked = true
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            try? await center.add(request)
        }
    }

    /// Asks for permission up front, from Settings.
    func requestPermission() async -> Bool {
        guard let center else { return false }
        asked = true
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func permissionStatus() async -> UNAuthorizationStatus {
        guard let center else { return .denied }
        return await center.notificationSettings().authorizationStatus
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let printer = notification.request.content.userInfo["printer"] as? String
        let onScreen = await MainActor.run {
            NSApp.isActive && UserDefaults.standard.string(forKey: "selectedInstance") == printer
        }
        return onScreen ? [] : [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let printer = response.notification.request.content.userInfo["printer"] as? String
        await MainActor.run {
            // Clicking a notification shows that printer.
            if let printer { UserDefaults.standard.set(printer, forKey: "selectedInstance") }
            NSApp.activate()
        }
    }
}
