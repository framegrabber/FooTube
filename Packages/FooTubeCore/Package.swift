// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "FooTubeCore",
    platforms: [.tvOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "FooTubeCore", targets: ["FooTubeCore"]),
    ],
    targets: [
        .target(name: "FooTubeCore", swiftSettings: strict),
    ],
)
