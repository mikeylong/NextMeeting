// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NextMeeting",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NextMeeting", targets: ["NextMeeting"]),
    ],
    targets: [
        .executableTarget(name: "NextMeeting", path: "Sources/NextMeeting"),
    ]
)
