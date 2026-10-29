import Foundation
import OctoPrintKit

/// A plugin OctoPrint is installing from its plugin list, with the log it sends as it goes.
struct PluginInstall: Equatable {
    enum Outcome: Equatable {
        case installed(needsRestart: Bool)
        case failed(String)
    }

    var plugin: RepositoryPlugin
    var log: [String] = []
    var outcome: Outcome?
    /// OctoPrint has restarted since, so the plugin is running.
    var restarted = false

    var isRunning: Bool { outcome == nil }
}

/// A few real plugins for demo mode, and a pretend install log.
enum DemoPlugins {
    static let repository: [RepositoryPlugin] = [
        demo("octolapse", "Octolapse", "FormerLurker", "Create stabilized timelapses of your 3D prints.", users: 41_000),
        demo("bedlevelvisualizer", "Bed Visualizer", "jneilliii", "Displays 3D mesh of bed topography report.", users: 14_700),
        demo("prusaslicerthumbnails", "Slicer Thumbnails", "jneilliii", "Extracts thumbnails from G-code made by PrusaSlicer, SuperSlicer, Cura and others.", users: 33_000),
        demo("PrintTimeGenius", "Print Time Genius", "Eyal", "Use a gcode pre-analysis to provide better print time estimation.", users: 22_000),
        demo("cancelobject", "Cancel Objects", "Paul Paukstelis", "Cancel individual objects while printing.", users: 11_000),
        demo("DisplayLayerProgress", "DisplayLayerProgress", "Olli", "Shows the current layer and height while printing.", users: 26_000),
        demo("firmwareupdater", "Firmware Updater", "Ben Lye", "Flash firmware to your printer straight from OctoPrint.", users: 9_800),
        demo("themeify", "Themeify", "Birk Johansson", "Beautify OctoPrint with themes and custom colours.", users: 7_200, compatible: false),
        demo("oldwebcamhelper", "Old Webcam Helper", "Someone", "Helps with webcams on very old versions of OctoPrint.", users: 300, abandoned: true),
    ]

    private static func demo(_ id: String, _ title: String, _ author: String, _ summary: String, users: Int,
                             compatible: Bool = true, abandoned: Bool = false) -> RepositoryPlugin {
        RepositoryPlugin(id: id, title: title, summary: summary, author: author,
                         homepage: URL(string: "https://plugins.octoprint.org/plugins/\(id)/"),
                         page: URL(string: "https://plugins.octoprint.org/plugins/\(id)/"),
                         archive: URL(string: "https://example.com/\(id).zip")!,
                         compatible: compatible, abandoned: abandoned, users: users)
    }

    static func installLog(for plugin: RepositoryPlugin) -> [String] {
        [
            "Installing plugin from \(plugin.archive.absoluteString)",
            "/home/pi/oprint/bin/python -m pip install \(plugin.archive.absoluteString)",
            "Collecting \(plugin.archive.absoluteString)",
            "Downloading \(plugin.id).zip (41 kB)",
            "Building wheels for collected packages: \(plugin.id)",
            "Successfully built \(plugin.id)",
            "Installing collected packages: \(plugin.id)",
            "Successfully installed \(plugin.id)-1.0.0",
            "Done!",
        ]
    }
}
