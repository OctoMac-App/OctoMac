import Foundation
import Observation

/// G-code files opened from Finder (Open With, or dropped on the Dock icon), waiting for a printer to go to.
@MainActor
@Observable
final class FileInbox {
    static let shared = FileInbox()
    var pending: [URL] = []

    static let extensions: Set<String> = ["gcode", "gco", "g", "bgcode"]

    func receive(_ urls: [URL]) {
        let files = urls.filter { $0.isFileURL && Self.extensions.contains($0.pathExtension.lowercased()) }
        guard !files.isEmpty else { return }
        pending.append(contentsOf: files)
    }
}
