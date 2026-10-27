// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "FooTubeCore",
    platforms: [.tvOS(.v18), .iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "FooTubeCore", targets: ["FooTubeCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/alexeichhorn/YouTubeKit", exact: "0.4.9"),
        .package(path: "../InnerTubeKit"),
    ],
    targets: [
        .target(
            name: "FooTubeCore",
            dependencies: [
                .product(name: "YouTubeKit", package: "YouTubeKit"),
                .product(name: "InnerTubeKit", package: "InnerTubeKit"),
            ],
            swiftSettings: strict,
        ),
        .testTarget(
            name: "FooTubeCoreTests",
            dependencies: ["FooTubeCore", .product(name: "InnerTubeKit", package: "InnerTubeKit")],
            resources: [.copy("Fixtures")],
            swiftSettings: strict,
        ),
    ],
)
