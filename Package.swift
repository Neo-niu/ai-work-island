// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexTouchBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "CodexTouchBar", targets: ["CodexTouchBar"]),
        .executable(name: "CodexStatusWidget", targets: ["CodexStatusWidget"]),
        .library(name: "CodexTouchBarCore", targets: ["CodexTouchBarCore"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .target(
            name: "CodexTouchBarCore",
            dependencies: ["CSQLite"],
            path: "Sources/CodexTouchBarCore"
        ),
        .target(
            name: "PrivateTouchBar",
            path: "Sources/PrivateTouchBar",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "CodexTouchBar",
            dependencies: [
                "CodexTouchBarCore",
                "PrivateTouchBar",
            ],
            path: "Sources/CodexTouchBar",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "CodexStatusWidget",
            dependencies: ["CodexTouchBarCore"],
            path: "Sources/CodexStatusWidget",
            swiftSettings: [
                .unsafeFlags(["-application-extension", "-parse-as-library"]),
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("WidgetKit"),
            ]
        ),
        .testTarget(
            name: "CodexTouchBarCoreTests",
            dependencies: ["CodexTouchBarCore", "CSQLite"],
            path: "Tests/CodexTouchBarCoreTests"
        ),
        .testTarget(
            name: "CodexTouchBarUITests",
            dependencies: ["CodexTouchBar", "CodexTouchBarCore"],
            path: "Tests/CodexTouchBarUITests"
        ),
    ]
)
