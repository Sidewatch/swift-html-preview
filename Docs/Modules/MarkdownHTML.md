# Swift Markdown HTML

A small Markdown → HTML renderer built on Apple's [swift-markdown](https://github.com/apple/swift-markdown) (cmark-gfm) — its only dependency. Give it a CommonMark + GitHub-Flavored-Markdown string and get back an HTML fragment: one static call, no configuration.

## Features

- 📝 **One call** — `MarkdownHTML.render(_:)` takes a Markdown string, returns an HTML fragment
- 🐙 **CommonMark + GFM** — headings, emphasis, nested lists, block quotes, plus tables, task lists (`<li class="task">` with disabled checkboxes), and strikethrough
- 🧱 **Code blocks** — fenced blocks emit `class="language-…"` on `<code>` for syntax highlighters; the info string is attribute-escaped so it can't inject markup
- ∑ **Math spans** — `$…$` and `$$…$$` (GitHub's and pandoc's reading: "$5 and $10" is prose, nothing in code is math, `\$` is a dollar) come out as `<span class="math math-inline">` / `<span class="math math-display">` holding the TeX untouched and HTML-escaped, for the host's KaTeX or MathJax; `render(_:math: false)` switches it off
- 📈 **Diagram fences** — a ```` ```mermaid ```` block renders as `<pre class="mermaid">` holding its escaped source (GitHub's shape), for the host's renderer to replace; `render(_:diagramFences:)` chooses the tags, `[]` makes every fence code
- 🛡️ **Escaped output** — text and code are HTML-escaped, link/image attributes are quote-escaped; raw HTML in the source passes through verbatim
- 🔗 **URL sanitization** — `javascript:`, `vbscript:`, and `data:` link destinations are neutralized to `#` (whitespace/case obfuscation included); image sources allow `data:image/` only
- 🪶 **One dependency** — Apple's swift-markdown, nothing else
- 🍎 **Cross-platform** — iOS, macOS, tvOS, watchOS, visionOS
- 🧪 **Fully tested** — 27 unit tests covering every construct plus the escaping and URL-sanitization edge cases

## Requirements

- macOS 14+ (Foundation only; other Apple platforms at SwiftPM's default minimums)
- Swift 6.2+ (Swift 6 language mode)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-markdown-html.git", branch: "main")
]
```

## Usage

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
MarkdownHTML.render("```swift\nlet x = 1\n```")
// <pre><code class="language-swift">let x = 1\n</code></pre>

// Dangerous destinations are neutralized, not passed through.
MarkdownHTML.render("[click](javascript:alert(1))")
// <p><a href="#">click</a></p>
```

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT
