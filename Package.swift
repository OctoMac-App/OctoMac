// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OctoMac",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "OctoMac", targets: ["OctoMac"]),
        .library(name: "OctoPrintKit", targets: ["OctoPrintKit"]),
    ],
    targets: [
        // Platform-agnostic client for the OctoPrint REST + push (websocket) APIs.
        .target(name: "OctoPrintKit"),

        // The SwiftUI Mac app.
        .executableTarget(
            name: "OctoMac",
            dependencies: ["OctoPrintKit"],
            linkerSettings: [
                // Embed Info.plist so `swift run` gets the same ATS / bundle settings as the packaged .app.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Support/Info.plist"]),
            ]
        ),

        .testTarget(
            name: "OctoPrintKitTests",
            dependencies: ["OctoPrintKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
