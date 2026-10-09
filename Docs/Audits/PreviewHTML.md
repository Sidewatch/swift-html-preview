# Audit log

Last full audit: **24 Sep 2026** — the day the package was extracted from Sidewatch's app target
(`SidewatchQuickLookCore`), where the code render had shipped behind `--selftest-quicklook`, and
the table, database and Markdown renderers were added with their tests. Add a dated line under
*History* when you audit again, and keep *Known non-issues* current so the next pass skips them.

## What a full audit checks

1. `swift build` warnings (none allowed except those listed under known non-issues) and `swift test` green.
2. Dead code: every `func`/type/property declared once and referenced nowhere in the package or the family.
   Public API is NOT dead because Sidewatch does not call it.
3. Every public declaration documented with `///`.
4. The README's usage sample compiles against the current API.
5. Every cell, title and note that came from a file passes through `PreviewPage.escape`.

## Known non-issues

- `HighlightTheme.colors` is a global in swift-code-highlighting; the swap restores it after each render.
- The database renderer opens the file through `SQLiteDB.openForReading` — read-only, with the one measured exception (a WAL database without its sidecars, SQLITE_CANTOPEN); a file that is not SQLite never reaches it (the header decides). Before 9 Oct 2026 it opened read-write, which left `-wal` / `-shm` beside every WAL database it rendered.
- The Markdown page carries no script: Mermaid is source, math is MathML from swift-markdown-html.

## History

- 24 Sep 2026 — extracted and extended; eight tests.
- 24 Sep 2026, later — the strip removed, database tables as CSS-radio tabs, the live filter, archives through swift-archive-index, the binary sniff, HighlightedHTML for every code path; eleven tests; mutants: no script (1 failure), no panel rule (1), no binary sniff (1).
- 9 Oct 2026 — `DatabasePreviewHTML` renders through `SQLiteDB.openForReading` (read-only; the WAL-without-sidecars fallback documented on it). Tests: `DatabasePreviewHTMLTests` (a rollback database leaves no journal; a sidecar-less WAL database still renders). Mutant: the plain read-only open with no fallback fails the WAL test (`No tables.`).
