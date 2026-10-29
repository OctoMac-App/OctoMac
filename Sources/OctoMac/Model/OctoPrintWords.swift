import Foundation
import OctoPrintKit

/// OctoPrint reports some things in English: the printer's connection state and its own system commands. These are
/// the standard ones it always uses, in the app's language. Anything else (a plugin's state, a command you added
/// yourself) is shown exactly as OctoPrint sent it.
enum OctoPrintWords {
    static func state(_ text: String) -> String {
        switch text {
        case "Offline": String(localized: "Offline")
        case "Opening serial connection": String(localized: "Opening serial connection")
        case "Detecting serial connection": String(localized: "Detecting serial connection")
        case "Detecting baudrate": String(localized: "Detecting baud rate")
        case "Connecting": String(localized: "Connecting")
        case "Operational": String(localized: "Operational")
        case "Starting": String(localized: "Starting")
        case "Starting print from SD": String(localized: "Starting print from SD card")
        case "Starting to send file to SD": String(localized: "Starting to send file to SD card")
        case "Printing": String(localized: "Printing")
        case "Printing from SD": String(localized: "Printing from SD card")
        case "Sending file to SD", "Transferring file to SD": String(localized: "Sending file to SD card")
        case "Pausing": String(localized: "Pausing")
        case "Paused": String(localized: "Paused")
        case "Resuming": String(localized: "Resuming")
        case "Finishing": String(localized: "Finishing")
        case "Cancelling": String(localized: "Cancelling")
        case "Closed": String(localized: "Closed")
        case "Offline after error": String(localized: "Offline after error")
        default:
            if text.hasPrefix("Error: ") { String(localized: "Error: \(String(text.dropFirst(7)))") }
            else if text.hasPrefix("Offline after error: ") { String(localized: "Offline after error: \(String(text.dropFirst(21)))") }
            else { text }
        }
    }

    /// A system command's name: OctoPrint's own (restart, reboot, shut down) in the app's language, others as written.
    static func commandName(_ command: SystemCommand) -> String {
        guard command.source == "core" else { return command.name }
        switch command.action {
        case "restart": return String(localized: "Restart OctoPrint")
        case "restart_safe": return String(localized: "Restart OctoPrint in safe mode")
        case "reboot": return String(localized: "Reboot system")
        case "shutdown": return String(localized: "Shut down system")
        default: return command.name
        }
    }

    /// What OctoPrint asks before running a command, in the app's language for its own commands.
    static func commandConfirmation(_ command: SystemCommand) -> String? {
        guard command.source == "core" else { return command.confirm }
        switch command.action {
        case "restart", "restart_safe": return String(localized: "You're about to restart the OctoPrint server.")
        case "reboot": return String(localized: "You're about to reboot the Raspberry Pi.")
        case "shutdown": return String(localized: "You're about to shut down the Raspberry Pi. You'll need to switch it on again yourself.")
        default: return command.confirm
        }
    }
}
