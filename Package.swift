// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MyRemote",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),
        // Already pulled in by Hummingbird; named here because the Host uses their types directly.
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        // Updates the Release build from GitHub Releases (see scripts/dmg.sh).
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.10.0"),
    ],
    targets: [
        // Pure logic the Host runs: the wire protocol, pointer math and Pairing. No AppKit, no I/O.
        .target(name: "HostCore"),
        // The menubar app: serves the Remote, turns commands into CGEvents.
        .executableTarget(
            name: "MyRemoteHost",
            dependencies: [
                "HostCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            // scripts/bundle.sh puts Sparkle.framework in the app's Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "HostCoreTests", dependencies: ["HostCore"]),
    ]
)
