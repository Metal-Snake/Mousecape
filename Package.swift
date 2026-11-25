// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mousecape",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // The original cursor engine (Objective-C, manual retain/release): applies, backs up
        // and restores cursors through private CoreGraphics (CGS/CoreCursor) calls.
        .target(
            name: "MousecloakCore",
            cSettings: [
                .unsafeFlags(["-fno-objc-arc"]),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
        // Reading .cape files and rendering cursor frames. Pure Swift, no private API.
        .target(
            name: "CapeKit"
        ),
        // The background agent's launchd job and the user's choice whether it runs, shared
        // by the app and `mousecloak --repair-agent`.
        .target(
            name: "LoginAgentKit"
        ),
        // Command line tool; `mousecloak --listen` is also the background agent that
        // re-applies the cape at login and on display changes.
        .executableTarget(
            name: "mousecloak",
            dependencies: ["MousecloakCore", "CapeKit", "LoginAgentKit"]
        ),
        // SwiftUI app.
        .executableTarget(
            name: "Mousecape",
            dependencies: ["MousecloakCore", "CapeKit", "LoginAgentKit"]
        ),
        // File builders shared by the test targets.
        .target(
            name: "TestSupport",
            path: "Tests/TestSupport"
        ),
        .testTarget(
            name: "CapeKitTests",
            dependencies: ["CapeKit", "TestSupport"]
        ),
        .testTarget(
            name: "MousecapeTests",
            dependencies: ["Mousecape", "CapeKit", "MousecloakCore", "LoginAgentKit", "TestSupport"]
        ),
    ]
)
