// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PreviewHTML",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PreviewHTML", targets: ["PreviewHTML"]),
    ],
    dependencies: [
        .package(path: "../swift-code-language"),
        .package(path: "../swift-code-highlighting"),
        .package(path: "../swift-markdown-html"),
        .package(path: "../swift-data-converter"),
        .package(path: "../swift-sqlite-reader"),
        .package(path: "../swift-archive-index"),
    ],
    targets: [
        .target(name: "PreviewHTML",
                dependencies: [
                    .product(name: "CodeLanguage", package: "swift-code-language"),
                    .product(name: "CodeHighlighting", package: "swift-code-highlighting"),
                    .product(name: "MarkdownHTML", package: "swift-markdown-html"),
                    .product(name: "DataConverter", package: "swift-data-converter"),
                    .product(name: "SQLiteReader", package: "swift-sqlite-reader"),
                    .product(name: "ArchiveIndex", package: "swift-archive-index"),
                ],
                path: "Sources", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "PreviewHTMLTests", dependencies: ["PreviewHTML"], path: "Tests"),
    ]
)
