// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MyRemote",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),
    ],
    targets: [
        // Pure logic the Host runs: the wire protocol and pointer math. No AppKit, no I/O.
        .target(name: "HostCore"),
        // The menubar app: serves the Remote, turns commands into CGEvents.
        .executableTarget(
            name: "MyRemoteHost",
            dependencies: [
                "HostCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ]
        ),
        .testTarget(name: "HostCoreTests", dependencies: ["HostCore"]),
    ]
)
