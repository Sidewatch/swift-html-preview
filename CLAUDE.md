# Swift Preview HTML

A file on disk as the HTML page a data-based Quick Look preview answers with: a SQLite database
(known by its 16-byte header, whatever its name) as its tables with columns, counts and first rows;
CSV (quote-aware, `DataConverter.csvRecords`) and TSV as a table; Markdown rendered through
`MarkdownHTML` with fenced code coloured; everything else as line-numbered source coloured by
`CodeHighlighting`'s tree-sitter HTML. All of it in a host app's theme, handed over as
`ThemeSnapshot` — resolved hexes in a JSON file the sandboxed extension can read — and put on the
highlighter for one render by `HighlightThemeSwap`, then taken off (a host rendering in-process
keeps its own provider).

- Module `PreviewHTML` in `Sources/PreviewHTML`; tests in `Tests`; `swift test` is the whole check (the database test builds its fixture with `/usr/bin/sqlite3`).
- Depends on the family: swift-code-language, swift-code-highlighting, swift-markdown-html, swift-data-converter, swift-sqlite-reader (path deps). macOS 14, tools 6.2, Swift 6.
- The highlighter's entry is main-actor, so `FilePreviewHTML.render` is; an extension hops to main for it.
- Grammar query bundles must sit beside the running binary (`Bundle.main`); the host's bundling copies them into the appex.
- No script ever runs in a preview page: Mermaid fences stay as source, math is MathML.

@CONTRIBUTING.md
