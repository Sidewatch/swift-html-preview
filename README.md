# Swift HTML Preview

Files as HTML pages: Markdown rendered through Apple's swift-markdown, and the full preview page Quick Look answers with for code, data, databases and archives.

## Modules

Each module is its own library product: depend on the package, then only on the products you use.

| Module | What it is |
|---|---|
| [`MarkdownHTML`](Docs/Modules/MarkdownHTML.md) | Markdown → HTML through Apple's swift-markdown (cmark-gfm). |
| [`PreviewHTML`](Docs/Modules/PreviewHTML.md) | A file on disk as the HTML page a Quick Look preview answers with: code, data, SQLite databases, archives, Markdown. |

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-html-preview.git", from: "0.1.0")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "MarkdownHTML", package: "swift-html-preview"),
    ]),
]
```

## Requirements

- macOS 14+
- Swift 6.2+ (Swift 6 language mode)

## History

The modules were separate packages until 27 September 2026 (`swift-markdown-html`, `swift-preview-html`); their commits are kept here, so `git log --follow` traces any file back through them.

## Licence

MIT — see [LICENSE](LICENSE).
