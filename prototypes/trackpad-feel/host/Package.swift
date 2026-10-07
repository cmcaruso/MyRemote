// swift-tools-version:6.0
// PROTOTYPE (throwaway): trackpad-feel Host for ticket #7. Not production code.
import PackageDescription

let package = Package(
    name: "TrackpadHost",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "TrackpadHost",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ]
        )
    ]
)
