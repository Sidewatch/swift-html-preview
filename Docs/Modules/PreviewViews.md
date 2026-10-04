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
- `ZipArchiveView` — a zip-shaped or tar archive as a tree, read off the main thread.
- `CSVTableView` — CSV/TSV as a grid; `isReadOnly` keeps cells as labels.
- `JSONTreeView` — JSON and every `TreeFormat` (YAML, TOML, XML, plist, INI, .properties, .strings, JSON
  Lines) as a tree; `isReadOnly`.
- `RecordTableView` — `RecordFormat` files as rows; `isReadOnly` drops edits and enable switches.
- `CodePreviewView` — source in the palette's editor font with the highlighter's tiers and a
  `LineNumberGutter`; the first `highlightCap` characters are coloured.

The views draw through `PreviewViews.palette` (a `PreviewViewsPalette`) and redraw on
`PreviewViews.themeDidChange`.
