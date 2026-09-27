# Swift HTML Preview

Files as HTML pages: Markdown rendered through Apple's swift-markdown, and the full preview page Quick Look answers with for code, data, databases and archives.

## Modules

Each module is its own library product: depend on the package, then only on the products you use.

| Module | What it is |
|---|---|
| [`MarkdownHTML`](Docs/Modules/MarkdownHTML.md) | Markdown → HTML through Apple's swift-markdown (cmark-gfm). |
| [`PreviewHTML`](Docs/Modules/PreviewHTML.md) | A file on disk as the HTML page a Quick Look preview answers with: code, data, SQLite databases, archives, Markdown. |

## Requirements

- macOS 14+
- Swift 6.2+ (Swift 6 language mode)

## Installation

### Swift Package Manager

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

## Usage

### MarkdownHTML

```swift
import MarkdownHTML

// One static call: Markdown in, HTML fragment out.
let html = MarkdownHTML.render("""
# Hello

Some **bold** text and a [link](https://apple.com).

- [x] shipped
- [ ] todo
""")

print(html)
// <h1>Hello</h1>
// <p>Some <strong>bold</strong> text and a <a href="https://apple.com">link</a>.</p>
// <ul>
// <li class="task"><input type="checkbox" disabled checked>shipped</li>
// <li class="task"><input type="checkbox" disabled>todo</li>
// </ul>

// Fenced code blocks carry the language for client-side highlighters.
MarkdownHTML.render("```

### PreviewHTML

See [Docs/Modules/PreviewHTML.md](Docs/Modules/PreviewHTML.md).

Each module's full guide is `Docs/Modules/<Module>.md`.

## Notes

The modules were separate packages until 27 September 2026 (`swift-markdown-html`, `swift-preview-html`); their commits are kept here, so `git log --follow` traces any file back through them.

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT — see [LICENSE](LICENSE).
