// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DraftKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DraftKit", targets: ["DraftKit"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
        .package(url: "https://github.com/swiftlang/swift-cmark.git", from: "0.6.0"),
    ],
    targets: [
        .target(name: "DraftKit", dependencies: [
            .product(name: "Markdown", package: "swift-markdown"),
            .product(name: "cmark-gfm", package: "swift-cmark"),
            .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
        ]),
        .testTarget(name: "DraftKitTests", dependencies: ["DraftKit"], resources: [.copy("Fixtures")]),
    ]
)
