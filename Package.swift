// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-html-preview",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownHTML", targets: ["MarkdownHTML"]),
        .library(name: "PreviewHTML", targets: ["PreviewHTML"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", branch: "main"),
        .package(path: "../swift-foundation-extensions"),
        .package(path: "../swift-appkit-ui"),
        .package(path: "../swift-code-kit"),
        .package(path: "../swift-data-converter"),
        .package(path: "../swift-sqlite-reader"),
        .package(path: "../swift-archive-index"),
    ],
    targets: [
        .target(
            name: "MarkdownHTML", dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "PreviewHTML",
            dependencies: [
                "MarkdownHTML",
                .product(name: "CodeLanguage", package: "swift-code-kit"),
                .product(name: "CodeHighlighting", package: "swift-code-kit"),
                .product(name: "FoundationExtensions", package: "swift-foundation-extensions"),
                .product(name: "AppKitViews", package: "swift-appkit-ui"),
                .product(name: "DataConverter", package: "swift-data-converter"),
                .product(name: "SQLiteReader", package: "swift-sqlite-reader"),
                .product(name: "ArchiveIndex", package: "swift-archive-index"),
            ],
            resources: [.process("Localizable.xcstrings")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "MarkdownHTMLTests", dependencies: ["MarkdownHTML"]),
        .testTarget(name: "PreviewHTMLTests", dependencies: ["PreviewHTML"]),
    ]
)
