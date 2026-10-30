import AppKit
import Foundation
import UserNotifications

/// The kinds of thing OctoMac can tell you about, each with its own switch in Settings.
enum NotificationKind: String, CaseIterable, Identifiable {
    case printDone, printFailed, firstLayer, layerReached, scheduled, needsAttention, printerMessages, printerProblem, piWarning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .printDone: String(localized: "Print finished")
        case .printFailed: String(localized: "Print failed or stopped")
        case .firstLayer: String(localized: "First layer done")
        case .layerReached: String(localized: "Layer alerts")
        case .scheduled: String(localized: "Scheduled and queued prints")
        case .needsAttention: String(localized: "Printer needs you")
        case .printerMessages: String(localized: "Messages from the printer")
        case .printerProblem: String(localized: "Printer stopped answering")
        case .piWarning: String(localized: "Raspberry Pi warnings")
        }
    }

    var detail: String {
        switch self {
        case .printDone: String(localized: "When a print completes.")
        case .printFailed: String(localized: "When a print fails, or is stopped from the printer.")
        case .firstLayer: String(localized: "A camera picture once the first layer is down, so you can catch a bad start early.")
        case .layerReached: String(localized: "When a print reaches a layer you chose to be told about or pause at.")
        case .scheduled: String(localized: "When a scheduled print starts, and when the next print in the queue is ready to go.")
        case .needsAttention: String(localized: "Filament changes, a paused print, a question from the printer, or a filament choice for the Prusa MMU.")
        case .printerMessages: String(localized: "Status messages the printer's firmware sends, such as “Heating done”. Some printers send a lot, so this starts off.")
        case .printerProblem: String(localized: "When the printer reports an error or drops its connection mid-print.")
        case .piWarning: String(localized: "Low power or overheating on the Raspberry Pi, which can spoil prints.")
        }
    }

    var defaultsKey: String { "notify.\(rawValue)" }

    /// Whether this kind of notification comes with a picture from the printer's camera.
    var showsCamera: Bool {
        switch self {
        case .printDone, .printFailed, .firstLayer, .layerReached, .scheduled, .needsAttention: true
        case .printerMessages, .printerProblem, .piWarning: false
        }
    }

    /// The Settings switch for camera pictures in notifications. On unless you turn it off.
    static let cameraKey = "notify.camera"
    static var includesCamera: Bool { UserDefaults.standard.object(forKey: cameraKey) as? Bool ?? true }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? isOnUntilChanged
    }

    /// Most kinds are on until you switch them off; chatty ones start off.
    var isOnUntilChanged: Bool { self != .printerMessages }
}

/// Buttons a notification can offer.
enum NotificationActions: String {
    /// Pause and Stop Print, for checking on a print in progress.
    case printControls
    /// Start the next print in the queue, once you've cleared the bed.
    case queueNext

    static let pause = "pause"
    static let stop = "stop"
    static let startNext = "startNext"

    var category: UNNotificationCategory {
        switch self {
        case .printControls:
            UNNotificationCategory(identifier: rawValue, actions: [
                UNNotificationAction(identifier: Self.pause, title: String(localized: "Pause"), options: []),
                UNNotificationAction(identifier: Self.stop, title: String(localized: "Stop Print"), options: [.destructive]),
            ], intentIdentifiers: [])
        case .queueNext:
            UNNotificationCategory(identifier: rawValue, actions: [
                UNNotificationAction(identifier: Self.startNext, title: String(localized: "Bed's Clear, Start Next"), options: []),
            ], intentIdentifiers: [])
        }
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
    /// Runs a notification button (Pause or Stop Print) for a printer. Set by the instance store.
    var onAction: ((UUID, String) -> Void)?
    /// Messages already sent recently, so a burst of identical events makes one banner.
    private var recent: [String: Date] = [:]

    /// Sets up delivery and, the first time OctoMac runs, asks for permission so notifications work from the start.
    /// After that, each kind can be switched off in Settings.
    func start() {
        guard let center else { return }
        center.delegate = self
        center.setNotificationCategories([NotificationActions.printControls.category, NotificationActions.queueNext.category])
        Task {
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = await requestPermission()
            }
        }
    }

    /// `picture` is a JPEG from the printer's camera, shown in the notification when the kind and Settings allow it.
    func post(_ kind: NotificationKind, printer: Instance, title: String, body: String, picture: Data? = nil,
              actions: NotificationActions? = nil) {
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
        if let actions { content.categoryIdentifier = actions.rawValue }
        if kind.showsCamera, NotificationKind.includesCamera, let picture, let attachment = Self.attachment(picture) {
            content.attachments = [attachment]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        Task {
            if !asked {
                asked = true
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            try? await center.add(request)
        }
    }

    /// Notification pictures have to be files; macOS moves this one into its own store when the notification is added.
    private static func attachment(_ jpeg: Data) -> UNNotificationAttachment? {
        let url = FileManager.default.temporaryDirectory.appending(path: "OctoMac-notification-\(UUID().uuidString).jpg")
        do {
            try jpeg.write(to: url)
            return try UNNotificationAttachment(identifier: "camera", url: url, options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"])
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
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
        let action = response.actionIdentifier
        if action == NotificationActions.pause || action == NotificationActions.stop || action == NotificationActions.startNext {
            await MainActor.run {
                if let id = printer.flatMap(UUID.init(uuidString:)) { Notifier.shared.onAction?(id, action) }
            }
            return
        }
        await MainActor.run {
            // Clicking a notification shows that printer.
            if let printer { UserDefaults.standard.set(printer, forKey: "selectedInstance") }
            NSApp.activate()
        }
    }
}
