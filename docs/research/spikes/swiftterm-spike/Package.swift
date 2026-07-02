// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swiftterm-spike",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "swiftterm-spike",
            dependencies: ["SwiftTerm"]
        ),
        .executableTarget(
            name: "swiftterm-bench",
            dependencies: ["SwiftTerm"]
        ),
    ]
)
