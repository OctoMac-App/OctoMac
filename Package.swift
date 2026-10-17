// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OctoMac",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "OctoMac", targets: ["OctoMac"]),
        .executable(name: "OctoMacWidgets", targets: ["OctoMacWidgets"]),
        .library(name: "OctoPrintKit", targets: ["OctoPrintKit"]),
    ],
    dependencies: [
        // Automatic updates for builds downloaded from GitHub Releases.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Platform-agnostic client for the OctoPrint REST + push (websocket) APIs.
        .target(name: "OctoPrintKit"),

        // The status file OctoMac shares with its widgets.
        .target(name: "WidgetData"),

        // Desktop and Control Centre widgets, packaged as OctoMac.app/Contents/PlugIns/OctoMacWidgets.appex.
        .executableTarget(
            name: "OctoMacWidgets",
            dependencies: ["WidgetData"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                // Start through Foundation's extension entry point, as Xcode does for app extensions. With a plain
                // `main`, macOS's extension loader traps as soon as the widget system launches the extension.
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"]),
            ]
        ),

        // The SwiftUI Mac app.
        .executableTarget(
            name: "OctoMac",
            dependencies: ["OctoPrintKit", "WidgetData", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                // Sparkle.framework is copied into OctoMac.app/Contents/Frameworks by the build scripts.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                // Embed Info.plist so `swift run` gets the same ATS / bundle settings as the packaged .app.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Support/Info.plist"]),
            ]
        ),

        .testTarget(
            name: "OctoMacTests",
            dependencies: ["OctoMac"]
        ),

        .testTarget(
            name: "OctoPrintKitTests",
            dependencies: ["OctoPrintKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
