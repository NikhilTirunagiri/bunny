// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BunnyCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BunnyCore", targets: ["BunnyCore"])],
    targets: [
        .target(name: "BunnyCore", path: "bunny/Core"),
        .testTarget(
            name: "BunnyCoreTests",
            dependencies: ["BunnyCore"],
            path: "Tests/BunnyCoreTests",
            // Python fake CLIs, located via #filePath at test time; not resources.
            exclude: ["FakeCLIs"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
