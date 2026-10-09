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
