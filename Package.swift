// swift-tools-version: 5.9
import PackageDescription
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let appExcludes = ["assets", "Tests", "scripts", "dist", "Sources/LifeStatusCore", "README.md", "LICENSE"]
    .filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }

let package = Package(
    name: "LifeStatus",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LifeStatus", targets: ["LifeStatus"])],
    targets: [
        .target(name: "LifeStatusCore"),
        .executableTarget(name: "LifeStatus", dependencies: ["LifeStatusCore"], path: ".",
            exclude: appExcludes,
            sources: ["Sources/LifeStatus"], resources: [.copy("config")]),
        .testTarget(name: "LifeStatusCoreTests", dependencies: ["LifeStatusCore"])
    ]
)
