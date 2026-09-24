# Swift Preview HTML

A file on disk as the HTML page a data-based Quick Look preview answers with, decided by the BYTES
first: a SQLite database (its 16-byte header, whatever its name) as its tables, ONE TAB PER TABLE
(CSS radio inputs — no script), each with columns, count and first 200 rows; a zip or tar (its
signature, through swift-archive-index) as the tree of its members; a file with NUL bytes in its
first block gets nothing (TypeScript's `.ts` is also MPEG-2's, and the host claims that type); then
by name — CSV (quote-aware, `DataConverter.csvRecords`) and TSV as a table; Markdown rendered
through `MarkdownHTML` with fences coloured; everything else as line-numbered source coloured by
`HighlightedHTML` (the editor's three tiers, so SCSS and Less are coloured through the regex
tables). Every table of rows or members has a filter field in the sticky bar. No title strip. All of it in a host app's theme, handed over as
`ThemeSnapshot` — resolved hexes in a JSON file the sandboxed extension can read — and put on the
highlighter for one render by `HighlightThemeSwap`, then taken off (a host rendering in-process
keeps its own provider).

- Module `PreviewHTML` in `Sources/PreviewHTML`; tests in `Tests`; `swift test` is the whole check (the database test builds its fixture with `/usr/bin/sqlite3`).
- Depends on the family: swift-code-language, swift-code-highlighting, swift-markdown-html, swift-data-converter, swift-sqlite-reader, swift-archive-index (path deps). macOS 14, tools 6.2, Swift 6.
- The highlighter's entry is main-actor, so `FilePreviewHTML.render` is; an extension hops to main for it.
- Grammar query bundles must sit beside the running binary (`Bundle.main`); the host's bundling copies them into the appex.
- Scripts DO run in a Quick Look HTML preview (measured 24 Sep 2026: a four-second busy loop cost the WebContent process four seconds of CPU), which is what the filter uses; the tabs need none. Mermaid fences stay as source (the diagram library is the app's), math is MathML.

@CONTRIBUTING.md
