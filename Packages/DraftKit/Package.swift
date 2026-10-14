// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DraftKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DraftKit", targets: ["DraftKit"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
    ],
    targets: [
        .target(name: "DraftKit", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .testTarget(name: "DraftKitTests", dependencies: ["DraftKit"], resources: [.copy("Fixtures")]),
    ]
)
