# Audit log — PreviewViews

Last full audit: **4 Oct 2026**, the day the module was extracted from the app (the native preview
surfaces the app and its Quick Look extension share). Add a dated line under *History* when you
audit again, and keep *Known non-issues* current so the next pass skips them.

## What a full audit checks

1. `swift build` warnings (none allowed except those listed under known non-issues) and `swift test` green.
2. Dead code: every declaration referenced somewhere in the package or the family. Public API is NOT
   dead because Sidewatch does not call it.
3. Every public declaration documented with `///`.
4. Every test mutation-verified: break the view, watch its test fail, restore.

## Known non-issues

- A held-back load (a `load` during a cell edit) is applied one run-loop turn after the edit ends,
  not inside `controlTextDidEndEditing`: the field editor still holds the keyboard there, and a
  reload under it is the bug being avoided.
- `DatabaseView.fileIsWritable` stats the file on every editability question; the connection
  itself says nothing about the file (it is read-only until the first write).

## History

- 4 Oct 2026 — extracted; `NativePreviewTests`.
- 9 Oct 2026 — write paths. `CSVTableView` / `JSONTreeView` defer a `load` while a cell is being edited and
  replay it after (the CSV edit re-aimed at its record in the new text); `DatabaseView` browses through a
  read-only connection (`SQLiteDB.openForReading`), reopens read-write on the first write (`ensureWritable`),
  confirms a typed statement that can lose data (`confirmWrite`, `SQLStatementKind`) and deletes rows in one
  transaction. Tests: `EditInFlightTests`, `DatabaseViewTests`, `SQLStatementKindTests`. Mutants, each run and
  restored: no deferral (both edit tests fail, the typed value is dropped); the CSV edit not re-aimed (record 2
  for 3); delete without BEGIN/ROLLBACK (`["a", "c"]` for three rows); read-write browsing with no WAL fallback
  (four failures); typed statements unguarded (nothing asked, nothing written); a CTE always a write.
- 9 Oct 2026 — `ZipArchiveView.openMemberForTesting(row:)`: the double-click's unpack-and-open, for the
  corrupt-input harness's walk through a twenty-deep nested archive. No behaviour change.
- 27 Oct 2026 — `JSONTreeView.beginLoading(format:)`: a document read off the main thread empties the tree and says
  "Reading <format>…" once the read outlasts a moment; any load ends it. `TreeFormat.value(of:bytes:)` is
  `nonisolated`, so the host reads a big document off the main thread (Sidewatch does past 256 KB). Three mutants
  caught; the fourth (the reader back on the main actor) does not compile against the test that reads off main.
- 27 Oct 2026 (every timing in the 27 Oct entries was taken with the Mac heavily loaded — an AI model compiling — so
  read them as upper bounds; the structural fixes stand) — `CodePreviewView` lays out lazily (`allowsNonContiguousLayout`). Laid out whole, TextKit 1 typeset
  every line as the text view sized to fit, inside the initializer: measured in a release build, 267–301 ms for a
  1,000-line file (a 42 KB SystemVerilog sample, a 47 KB Python script) of which the highlight was 7–12 ms, and over
  Quick Look's 500 ms budget once the Mac was busy (522–655 ms in Sidewatch's corrupt-input check). After: 12–22 ms to
  build, 4 ms to the first draw, 3 ms to jump near the end, the gutter's numbers still on their lines (both ends drawn
  and looked at). `CodePreviewViewTests` pins it: 3,000 lines built and sized leave the text unlaid; the mutant (the
  line removed) fails it, taking 1.2 s instead of 0.14 s.
- 27 Oct 2026 — `CSVTableView` builds at most `columnCap` (250) columns and says so above the grid. NSTableView's
  `addTableColumn` costs time in proportion to the columns already there, whatever the autoresizing style, header
  cell, or whether the table is in a window or a scroll view at all (measured, release: a bare table took 1.0 s for
  2,000 columns, 4.6 s for 4,000, 28 s for 10,000). Sidewatch held its main thread 0.56 s opening a 1,000-column CSV,
  1.8 s switching back to its tab, and 48.6 s opening a 10,000-column one; Quick Look took 290 s late in a long run.
  Capped, Quick Look's path for a 10,000-column file is 80–140 ms to make and 140–157 ms to lay out; 500 columns cost
  148 ms to build against 250's 67, and the gate's late, loaded run doubled it past 500 ms, so the cap is 250.
  `CSVTableViewTests`: the cap, the note, the data under the last built column, the grid's top under the note and back
  at the top for a narrow file. Mutants, each run and restored: no cap (1,201 columns), no note, the grid never moved
  down, the grid always moved down — all caught. A first version that swapped two constraints let the last two
  survive (Auto Layout settled the ambiguity and broke the conflict by itself), so the grid's top is one constraint
  whose constant moves.
- 27 Oct 2026 — localisation: the Japanese and Korean drafts of "Showing the first %@ of %@ lines." put the total
  first without positional placeholders, so the counts read swapped; both now use `%2$@ … %1$@`. Every other ja/ko
  draft with two or more placeholders across the family's catalogs keeps the English order (scanned).
- 27 Oct 2026 — the tree's rows are built off the main thread. With the host's read already off it, a 2 MB JSON file
  still held the main thread 523–572 ms once the stall meter counted it: every row looked its type badge up through
  `String(localized:)` (a bundle lookup and a parse, per row: a 473 ms stall's stack), and building 120,000 `JSONItem`s
  took 170 ms of a 220 ms load after that. The badges are looked up once (`TreeTypeBadge`; the counted ones per count,
  behind a lock), and `JSONTreeView.prepare` builds the rows on any thread (`JSONItem`, its `Kind` and `PreparedTree`
  are `Sendable` and `nonisolated`), leaving the main thread the reload and the first expansion. `JSONTreeLoadingTests`:
  rows built on a background task load as rows built on the main thread — file order, paths, XML's rename rule.
  Mutants: the rule dropped from `prepare` (`[true, true, true]`), the prepared rows not loaded — both caught.
- 27 Oct 2026 — every preview table copies (David: "Copy to JSON, Copy to CSV… useful to share with your agent").
  `TableCopier`: Copy Row (tab-separated; also Edit ▸ Copy), Copy Cell, Copy as JSON, CSV and Markdown Table, and Copy as
  SQL INSERT for a browsed database table, in one place for the database grid, the CSV grid, the record tables and the
  `.env` table; the rows are `NSTableView.actionRows()` (Finder's rule). The database grid copies typed cells; its
  tables list and the diagram's boxes offer Copy Name and Copy CREATE Statement; a view, a typed query and a read-only
  file now get the copy items (Delete stays where a delete can run). Record tables' Copy Row kept only non-empty cells,
  shifting every column after one; the copies keep empty cells and an Enabled column where records switch off. The
  `.env` table's copies keep hidden values as bullets until Show values is on. The structure tree adds Copy jq Path.
  `TableCopyingTests` (6). Mutants, each run and restored: the grid's display text for its typed cells, a view taken as
  a table to insert into, a typed query keeping the browsed table (survived until the test browsed a table first),
  CSV fields dropped, record cells dropped, the Enabled column missing, hidden values in clear — all caught.

