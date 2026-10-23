// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexUsage",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexUsage", targets: ["CodexUsage"])],
    dependencies: [
        .package(url: "https://github.com/simibac/ConfettiSwiftUI.git", from: "3.0.0")
    ],
    targets: [
        .executableTarget(
            name: "CodexUsage",
            dependencies: ["ConfettiSwiftUI"],
            path: "Sources/CodexUsage"
        )
    ]
)
