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
                .unsafeFlags(["-Wno-deprecated-declarations"]),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        // Reading .cape files and rendering cursor frames. Pure Swift, no private API.
        .target(
            name: "CapeKit"
        ),
        // Command line tool; `mousecloak --listen` is also the background agent that
        // re-applies the cape at login and on display changes.
        .executableTarget(
            name: "mousecloak",
            dependencies: ["MousecloakCore", "CapeKit"]
        ),
        // SwiftUI app.
        .executableTarget(
            name: "Mousecape",
            dependencies: ["MousecloakCore", "CapeKit"]
        ),
        .testTarget(
            name: "CapeKitTests",
            dependencies: ["CapeKit"]
        ),
        .testTarget(
            name: "MousecapeTests",
            dependencies: ["Mousecape", "CapeKit", "MousecloakCore"]
        ),
    ]
)
