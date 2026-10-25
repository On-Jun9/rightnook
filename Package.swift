// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RightNook",
    platforms: [.macOS(.v14)],
    products: [.library(name: "RightNookCore", targets: ["RightNookCore"])],
    targets: [
        .target(name: "RightNookCore", path: "Sources/Core", resources: [.copy("Resources/FileTemplates")]),
        .testTarget(name: "RightNookCoreTests", dependencies: ["RightNookCore"], path: "Tests")
    ]
)
