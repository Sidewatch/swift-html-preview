# Swift Preview HTML

A file on disk as the HTML page a data-based Quick Look preview answers with: a SQLite database
as its tables, CSV and TSV as a table, Markdown rendered with its fences coloured, everything else
as line-numbered, syntax-coloured source — in a host app's theme, handed over as a snapshot of
resolved colours that a sandboxed extension can read. Extracted from
[Sidewatch](https://github.com/Sidewatch) on 24 Sep 2026, where it is the whole of the Quick Look
preview extension.

```swift
import PreviewHTML

// In the extension: the page for the file, in the host's theme (the snapshot the host wrote).
let html = FilePreviewHTML.render(fileAt: request.fileURL)                 // nil when unreadable

// In the host app, at launch and on every theme change:
try ThemeSnapshot(name: "Beacon", isDark: true, background: "#0F1117", …).write()   // ~/Library/Application Support/Sidewatch/quicklook-theme.json
```

The extension needs two things beside its binary and in its entitlements: the tree-sitter grammar
query bundles (`CodeHighlighting` looks for them in `Bundle.main`, which inside an appex is the
appex) and a read-only exception for the snapshot's folder
(`com.apple.security.temporary-exception.files.home-relative-path.read-only`), since inside the
sandbox `NSHomeDirectory()` is the container — `ThemeSnapshot.defaultURL` builds the path from the
passwd entry instead.

## Layout

- `Core/FilePreviewHTML.swift` — the one entry: kind by SQLite header, then extension, then language.
- `Renderers/` — `CodePreviewHTML`, `TablePreviewHTML`, `DatabasePreviewHTML`, `MarkdownPreviewHTML`.
- `Models/ThemeSnapshot.swift` — the host's theme as hexes; `Support/SnapshotColors.swift` puts it on the highlighter.
- `Support/HTML.swift` — escaping and the page around every body.
- `Tests/` — every kind through the entry, escaping, the caps, the snapshot; the database is built with `sqlite3`.

MIT. See CONTRIBUTING.md for the family rules.
