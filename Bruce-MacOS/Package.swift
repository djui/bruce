// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BruceMacOS",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BruceMacOS",
            path: "Sources/BruceMacOS",
            linkerSettings: [
                // Embed Info.plist (NSCameraUsageDescription) so the camera QR scanner can ask for access.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                              "-Xlinker", "Support/Info.plist"]),
            ]
        ),
        // Unit tests for the shared logic (Shared/BruceCore via the Shared symlink): `swift test`.
        .testTarget(name: "BruceCoreTests", dependencies: ["BruceMacOS"], path: "Tests/BruceCoreTests"),
    ]
)
