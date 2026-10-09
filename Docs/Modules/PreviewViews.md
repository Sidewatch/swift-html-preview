# PreviewViews

The native, read-only preview of a file, in AppKit views — the views a host app shows files in, and its
Quick Look extension can show too.

## Usage

```swift
import PreviewViews

PreviewViews.palette = MyPalette()          // or SnapshotPalette(ThemeSnapshot.load()!)
if let made = NativePreview.make(fileAt: url) {
    container.addSubview(made.view)          // made.kind: .database, .archive, .table, .tree, .records, .code
}
```

`NativePreview.make` decides by content (a SQLite header, an archive signature, NUL bytes) and then by
name and language. Markdown answers nil (it needs a web page), as do binary and unreadable files.
`NativePreview.wear(_:)` installs a `ThemeSnapshot` on the views, the themed controls and the highlighter.

## Views

- `DatabaseView` — tables, results grid, structure, ER diagram; `isReadOnly` hides the console and edits.
  The file is opened read-only to browse (`SQLiteDB.openForReading`: a read-write connection to a WAL
  database leaves `-wal` / `-shm` beside the user's file) and reopened read-write by `ensureWritable()` on
  the first write — a cell edit, + Row, Delete Row, or a typed statement `SQLStatementKind` says writes;
  one that can lose data (DELETE, UPDATE, DROP, ALTER) goes through the `confirmWrite` seam first, as
  Delete Row goes through `confirmDelete`. Delete Row runs its `DELETE … WHERE rowid = ?` statements in
  one transaction: a row a trigger refuses rolls the others back and the status keeps the error.
- `ZipArchiveView` — a zip-shaped or tar archive as a tree, read off the main thread.
- `CSVTableView` — CSV/TSV as a grid; `isReadOnly` keeps cells as labels. A `load` that arrives while a
  cell is being edited waits for the edit (`reloadData` under an open field editor ends it with the typed
  value lost) and the edit is aimed at the record it was made on wherever the new text holds it; the
  tree does the same by the node's path.
- `JSONTreeView` — JSON and every `TreeFormat` (YAML, TOML, XML, plist, INI, .properties, .strings, JSON
  Lines) as a tree; `isReadOnly`.
- `RecordTableView` — `RecordFormat` files as rows; `isReadOnly` drops edits and enable switches.
- `CodePreviewView` — source in the palette's editor font with the highlighter's tiers and a
  `LineNumberGutter`; the first `highlightCap` characters are coloured.

## Web

- `WebViewSeal` — the seal of a web view that shows a local page and must not phone home: `configuration(javaScript:)` (a non-persistent store), `arm(_:completion:)` (compiles `networkBlockRules`, one block rule per network scheme — WebKit's `url-filter` has no alternation — and adds it; the completion says whether the view is sealed), `allowsNavigation(to:)` (`file`, `about`, `data`, `blob` only). An app's own hardened view and its Quick Look extension both use this one implementation.
- `SealedWebView` — a `WKWebView` under the seal from its first load: a load asked for before the rules compile is queued, never run unsealed; the page's inline script runs (a filter field, a tab bar) while `fetch`, a WebSocket and a `location = "https://…"` are blocked; `blockedNavigations` records what was cancelled.

```swift
let web = SealedWebView(frame: bounds)              // javaScript: true by default
web.load(html: page, baseURL: folder)
```

The views draw through `PreviewViews.palette` (a `PreviewViewsPalette`) and redraw on
`PreviewViews.themeDidChange`.

## Support

- `SQLStatementKind` — what a script would do to a database (`read`, `write`, `destructive`) by its
  statements' leading verbs, comments skipped, a CTE judged by the verb after its definitions, a PRAGMA
  with a value counted as a write; `summary(of:)` names the verb and object for a confirmation.
