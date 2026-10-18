// swift-tools-version: 5.7
// Vendored from https://github.com/b5i/YouTubeKit (MIT) and renamed to InnerTubeKit — see VENDORED.md.
import PackageDescription

let package = Package(
    name: "InnerTubeKit",
    platforms: [.tvOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "InnerTubeKit", targets: ["InnerTubeKit"]),
    ],
    targets: [
        .target(
            name: "InnerTubeKit",
            resources: [.copy("JavaScript/.")],
        ),
    ],
)
