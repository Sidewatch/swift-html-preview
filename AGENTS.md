# Swift HTML Preview

Files as HTML pages: Markdown rendered through Apple's swift-markdown, and the full preview page Quick Look answers with for code, data, databases and archives.

- Modules `MarkdownHTML`, `PreviewHTML`, `PreviewViews`, each in `Sources/<Module>` with tests in `Tests/<Module>Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.
- Each module's user-facing documentation is `Docs/Modules/<Module>.md`; its last audit is `Docs/Audits/<Module>.md` — read it before auditing, and extend it rather than redo it.

## MarkdownHTML — `Sources/MarkdownHTML`

### Module map
- `Core/` — the engine: MarkdownHTML (`render(_:highlightCode:math:diagramFences:)`; a diagram fence is `<pre class="TAG">` of its source; a line's leading `>` markers are clamped to `maxBlockquoteDepth` before the parse), MathSpans (`$…$` / `$$…$$` lifted out before the parse as private-use placeholders and restored after as `.math` spans; fences, inline code and `\$` excluded)

## PreviewHTML — `Sources/PreviewHTML`


## PreviewViews — `Sources/PreviewViews`

### Module map
- `Web/` — WebViewSeal (the three seals of an offline web view: a non-persistent store, a compiled content rule list blocking every network scheme, local-only top-frame navigation — one implementation for an app and its Quick Look extension), SealedWebView (a `WKWebView` wearing it from its first load; the page's own inline script runs, `blockedNavigations` records what the seal cancelled)
- The rest is in `Docs/Modules/PreviewViews.md`: `NativePreview`, the views, the formats.


## Rules

Read `CONTRIBUTING.md` before changing anything: it is the layout and PR rulebook for this package.
