//
//  DatabaseView+Editing.swift
//  Sidewatch
//
//  DatabaseView: Cell editing + row insertion, Cell editor delegate (commit / cancel).
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import ThemedControls
import SQLiteReader
import UniformTypeIdentifiers
import FoundationExtensions
import AppKitViews
import DataConverter

extension DatabaseView {
    // MARK: - Cell editing + row insertion

    /// Double-click on a results cell: begin an inline edit for the canonical grid
    /// of an editable table; beep (with the grid's "read-only" tooltip set for
    /// views / WITHOUT ROWID tables) everywhere else.
    @objc public func cellDoubleClicked() {
        guard mode == .results, !isReadOnly else { return }  // structure grid is informational
        let row = resultsTable.clickedRow, displayCol = resultsTable.clickedColumn
        guard row >= 0, displayCol >= 0 else { return }
        guard editableTable != nil, rowIDs.indices.contains(row) else {
            NSSound.beep()  // view / WITHOUT ROWID / read-only file / custom query result
            return
        }
        // Columns can be user-reordered — map the clicked (display) column to the
        // model index carried in the `c<i>` identifier, like the cell builder does.
        guard let modelCol = Int(resultsTable.tableColumns[displayCol].identifier.rawValue.dropFirst()) else { return }
        beginCellEdit(row: row, col: modelCol)
    }

    /// Overlay the inline editor on the cell and focus it. `col` is the MODEL column
    /// index (into `result.columns`). Blob cells beep — their display placeholder
    /// can't round-trip as text.
    private func beginCellEdit(row: Int, col: Int) {
        endCellEdit(commit: true)
        guard let value = result.rows[safe: row]?[safe: col],
            let displayCol = resultsTable.tableColumns.firstIndex(where: { $0.identifier.rawValue == "c\(col)" })
        else { return }
        guard !value.hasPrefix("‹blob") else { NSSound.beep(); return }
        resultsTable.scrollRowToVisible(row)
        cellEditor.frame = resultsTable.frameOfCell(atColumn: displayCol, row: row).insetBy(dx: 0, dy: -1)
        cellEditor.stringValue = value
        resultsTable.addSubview(cellEditor)
        editSession = (row: row, col: col, original: value)
        window?.makeFirstResponder(cellEditor)
        cellEditor.currentEditor()?.selectAll(nil)
    }

    /// Tear down the inline editor, committing the value if it changed. Ends by
    /// replaying any same-file reload that arrived (and was deferred) mid-edit.
    public func endCellEdit(commit: Bool) {
        guard let session = editSession else { return }
        editSession = nil  // cleared FIRST — teardown re-fires controlTextDidEndEditing
        // Read the LIVE text: when ending from a path other than the field's own
        // end-editing notification (mode/table switch), stringValue can lag the editor.
        let text = cellEditor.currentEditor()?.string ?? cellEditor.stringValue
        if cellEditor.currentEditor() != nil { window?.makeFirstResponder(resultsTable) }
        cellEditor.removeFromSuperview()
        if commit, text != session.original {
            commitCellEdit(session, newText: text)
        }
        if pendingRefresh { pendingRefresh = false; refreshInPlace() }
    }

    /// Run the parameterized UPDATE for a committed cell edit, then re-read the row so the grid
    /// shows SQLite's stored form (affinity may coerce the text). Typing `NULL` stores SQL NULL.
    /// The write may MOVE the row: an `INTEGER PRIMARY KEY` column IS the rowid, so re-reading
    /// by the new rowid keeps `rowIDs` truthful — a stale entry would no-op every later edit to
    /// that row, then land on a stranger once SQLite recycles the freed rowid.
    private func commitCellEdit(_ session: (row: Int, col: Int, original: String), newText: String) {
        guard ensureWritable(), let db, let table = editableTable,
            let rid = rowIDs[safe: session.row],
            let colName = result.columns[safe: session.col]
        else { NSSound.beep(); return }
        let quotedTable = SQLiteDB.quoteIdentifier(table)
        let value: SQLiteDB.Value? = newText == "NULL" ? nil : .text(newText)
        let w = db.execute(
            "UPDATE \(quotedTable) SET \(SQLiteDB.quoteIdentifier(colName)) = ? WHERE rowid = ?",
            parameters: [value, .integer(rid)])
        if let err = w.error {
            setStatus(
                String(
                    localized: "Error: \(err)", bundle: .module,
                    comment: "Database console status; the placeholder is SQLite's error message"),
                error: true);
            return
        }
        guard w.rowsAffected > 0 else {
            // The captured rowid is gone (deleted underneath us) — never claim success.
            setStatus(
                String(
                    localized: "Row no longer exists (rowid \(String(rid))) — refreshed", bundle: .module,
                    comment: "Database status; the placeholder is a row id"), error: true)
            runCanonicalQuery(for: table); showResults()
            return
        }
        // Re-read with the rowid alongside: an unchanged row comes back at `rid`,
        // a re-keyed one at its new rowid (the value just written). Prefer `rid` —
        // an ordinary column edited to a number that happens to be another row's
        // rowid returns BOTH rows, and pairing the grid row with that stranger
        // would aim every later edit of this row at the wrong on-disk row.
        let newRID = Int64(newText) ?? rid
        let re = db.execute(
            "SELECT rowid, * FROM \(quotedTable) WHERE rowid IN (?, ?)",
            parameters: [.integer(rid), .integer(newRID)])
        let match = re.rows.first(where: { $0.first.flatMap(Int64.init) == rid }) ?? re.rows.first
        guard let fresh = match, fresh.count == result.columns.count + 1,
            let freshRID = Int64(fresh[0])
        else {
            // Can't locate the row — rebuild the grid so rows and rowIDs stay paired.
            runCanonicalQuery(for: table); showResults()
            setStatus(
                String(
                    localized: "Updated \(table).\(colName) — grid refreshed", bundle: .module,
                    comment: "Database status; the placeholders are a table and a column"), error: false)
            return
        }
        rowIDs[session.row] = freshRID
        replaceGridRow(session.row, with: Array(fresh.dropFirst()))
        setStatus(
            String(
                localized: "Updated \(table).\(colName) · rowid \(String(freshRID))", bundle: .module,
                comment: "Database status; the placeholders are a table, a column and a row id"), error: false)
    }

    /// Swap one grid row's values (both the displayed `result` and the cached
    /// `lastQueryResult` mode toggles restore from) and repaint just that row.
    private func replaceGridRow(_ row: Int, with values: [String]) {
        guard result.rows.indices.contains(row) else { return }
        var rows = result.rows
        rows[row] = values
        result = SQLiteDB.Result(columns: result.columns, rows: rows, error: nil, rowsAffected: 0)
        lastQueryResult = result
        resultsTable.reloadData(
            forRowIndexes: IndexSet(integer: row),
            columnIndexes: IndexSet(integersIn: 0..<result.columns.count))
    }

    /// "+ Row": insert a row of defaults (`INSERT INTO t DEFAULT VALUES`, falling
    /// back to explicit NULLs if that errors), refresh the grid, and begin editing
    /// the new row's first editable cell. A row landing beyond the LIMIT window is
    /// fetched and appended so it's still visible and editable.
    @objc public func addRow() {
        endCellEdit(commit: true)
        guard let table = editableTable, mode == .results, ensureWritable(), let db else { NSSound.beep(); return }
        let quotedTable = SQLiteDB.quoteIdentifier(table)
        var w = db.execute("INSERT INTO \(quotedTable) DEFAULT VALUES")
        if w.error != nil {
            let cols = db.schema(table)
            let names = cols.map { SQLiteDB.quoteIdentifier($0.name) }.joined(separator: ", ")
            let holes = cols.map { _ in "?" }.joined(separator: ", ")
            w = db.execute(
                "INSERT INTO \(quotedTable) (\(names)) VALUES (\(holes))",
                parameters: cols.map { _ in nil })
        }
        if let err = w.error {
            setStatus(
                String(
                    localized: "Error: \(err)", bundle: .module,
                    comment: "Database console status; the placeholder is SQLite's error message"),
                error: true);
            return
        }
        let newID = db.lastInsertRowID
        runCanonicalQuery(for: table)
        showResults()
        tableCounts[table] = db.rowCount(table)
        tableList.reloadData()
        if let sel = currentTable, let i = tables.firstIndex(of: sel) {
            tableList.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        }
        var newRow = rowIDs.firstIndex(of: newID)
        if newRow == nil, editableTable == table {
            let re = db.execute(
                "SELECT rowid, * FROM \(quotedTable) WHERE rowid = ?",
                parameters: [.integer(newID)])
            if let fresh = re.rows.first, fresh.count == result.columns.count + 1 {
                rowIDs.append(Int64(fresh[0]) ?? newID)
                var rows = result.rows
                rows.append(Array(fresh.dropFirst()))
                result = SQLiteDB.Result(columns: result.columns, rows: rows, error: nil, rowsAffected: 0)
                lastQueryResult = result
                resultsTable.reloadData()
                newRow = rows.count - 1
            }
        }
        setStatus(
            String(
                localized: "Row added · rowid \(String(newID))", bundle: .module, comment: "Database status; the placeholder is a row id"),
            error: false)
        guard let idx = newRow else { return }
        if let col = result.rows[safe: idx]?.firstIndex(where: { !$0.hasPrefix("‹blob") }) {
            beginCellEdit(row: idx, col: col)
        } else {
            resultsTable.scrollRowToVisible(idx)
        }
    }

    /// Deletes the selected row(s) — the other half of "+ Row". A DELETE is not undoable
    /// through the editor's undo stack (the file is the database, not a buffer), so it
    /// ASKS first, naming the table and the count, and it only ever runs `WHERE rowid = ?` —
    /// one statement per row, by the identity the grid already pairs with each line, inside
    /// ONE transaction: a row a trigger refuses rolls the others back, and the status keeps
    /// the error rather than a count.
    @objc public func deleteSelectedRows() {
        endCellEdit(commit: true)
        let rows = rowsForDelete()
        guard db != nil, let table = editableTable, mode == .results, !rows.isEmpty,
            rows.allSatisfy({ rowIDs.indices.contains($0) })
        else { NSSound.beep(); return }
        guard DatabaseView.confirmDelete(rows.count, table), ensureWritable(), let db else { return }
        let quoted = SQLiteDB.quoteIdentifier(table)
        if let err = db.run("BEGIN").error { showError(err); return }
        for row in rows.reversed() {
            let w = db.execute("DELETE FROM \(quoted) WHERE rowid = ?", parameters: [.integer(rowIDs[row])])
            if let err = w.error {
                _ = db.run("ROLLBACK")
                showError(err)
                return
            }
        }
        if let err = db.run("COMMIT").error {
            _ = db.run("ROLLBACK")
            showError(err)
            return
        }
        runCanonicalQuery(for: table)
        setMode(.results)
        tableCounts[table] = db.rowCount(table)
        tableList.reloadData()
        if let sel = currentTable, let i = tables.firstIndex(of: sel) {
            tableList.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        }
        setStatus(
            rows.count == 1
                ? String(localized: "Row deleted", bundle: .module) : String(localized: "\(rows.count) rows deleted", bundle: .module),
            error: false)
    }

    /// SQLite's error on the status line.
    private func showError(_ message: String) {
        setStatus(
            String(
                localized: "Error: \(message)", bundle: .module,
                comment: "Database console status; the placeholder is SQLite's error message"),
            error: true)
    }

    /// The connection a write needs. Browsing opened the file read-only (a read-write connection
    /// to a WAL database leaves `-wal` / `-shm` beside it); the first write replaces it with a
    /// read-write one. False, with the status saying so, when the file cannot be written.
    @discardableResult
    public func ensureWritable() -> Bool {
        guard let db else { return false }
        if !db.readOnly { return true }
        guard let url = currentURL, let writable = SQLiteDB(url: url, readOnly: false), !writable.readOnly else {
            setStatus(String(localized: "The database could not be opened for writing", bundle: .module), error: true)
            return false
        }
        self.db = writable
        return true
    }

    /// Opens `row` / `col` for editing, types `text` and commits — a double-click, typing and
    /// Return. For the harness.
    public func commitEditForTesting(row: Int, col: Int, text: String) {
        beginCellEdit(row: row, col: col)
        cellEditor.stringValue = text
        cellEditor.currentEditor()?.string = text
        endCellEdit(commit: true)
    }

    /// The rows a Delete would act on: the selection, or the row under a right-click when it is
    /// outside the selection (Finder's rule, the gallery's too).
    public func rowsForDelete() -> [Int] {
        let clicked = resultsTable.clickedRow
        let selected = resultsTable.selectedRowIndexes
        if clicked >= 0, !selected.contains(clicked) { return [clicked] }
        if clicked < 0, selected.isEmpty { return [] }
        return selected.sorted()
    }

    /// The confirmation, replaceable so the harness can answer it without a modal.
    public nonisolated(unsafe) static var confirmDelete: (_ count: Int, _ table: String) -> Bool = { count, table in
        MainActor.assumeIsolated {
            let alert = NSAlert(
                message: count == 1
                    ? String(localized: "Delete this row from “\(table)”?", bundle: .module)
                    : String(localized: "Delete \(count) rows from “\(table)”?", bundle: .module),
                information: String(localized: "This writes to the database straight away and cannot be undone.", bundle: .module),
                buttons: [
                    String(localized: "Delete", bundle: .module, comment: "Alert button: delete the database rows"),
                    String(localized: "Cancel", bundle: .module),
                ])
            return alert.runConfirmed()
        }
    }

    /// The confirmation before a typed statement that can lose data runs (DELETE, UPDATE, DROP,
    /// ALTER), replaceable so the harness answers it without a modal. `statement` is its verb and
    /// object ("DELETE FROM users").
    public nonisolated(unsafe) static var confirmWrite: (_ statement: String) -> Bool = { statement in
        MainActor.assumeIsolated {
            let alert = NSAlert(
                message: String(
                    localized: "Run “\(statement)”?", bundle: .module,
                    comment: "Alert before a typed SQL statement that can lose data runs; the placeholder is its verb and object"),
                information: String(localized: "This writes to the database straight away and cannot be undone.", bundle: .module),
                buttons: [
                    String(localized: "Run", bundle: .module, comment: "Alert button: run the SQL statement"),
                    String(localized: "Cancel", bundle: .module),
                ])
            return alert.runConfirmed()
        }
    }

    /// Sync the editing affordances to the visible grid: "+ Row" is enabled only
    /// over an editable canonical grid; non-editable canonical grids (views,
    /// WITHOUT ROWID tables, read-only files) carry the "read-only" tooltip.
    private func updateEditAffordances() {
        let resultsMode = mode == .results && !resultsScroll.isHidden
        let editable = resultsMode && editableTable != nil
        addRowButton.isEnabled = editable
        addRowButton.toolTip =
            editable
            ? String(localized: "Insert a row of defaults/NULLs", bundle: .module)
            : (gridReadOnlyHint
                ? String(localized: "read-only", bundle: .module, comment: "Tooltip: this database grid cannot be edited") : nil)
        resultsTable.toolTip =
            (resultsMode && gridReadOnlyHint)
            ? String(localized: "read-only", bundle: .module, comment: "Tooltip: this database grid cannot be edited") : nil
    }

    // MARK: - Cell editor delegate (commit / cancel)

    /// Return, Tab or focus loss in the inline editor — commit.
    public func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === cellEditor else { return }
        endCellEdit(commit: true)
    }

    /// Escape in the inline editor — cancel without committing.
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === cellEditor else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            endCellEdit(commit: false)
            return true
        }
        return false
    }

    /// The host picked a mode in the breadcrumb's surface menu; leaving Results commits any
    /// in-flight cell edit first.
    public func changeMode(to new: Mode) {
        endCellEdit(commit: true)
        setMode(new)
    }

    /// Swap the diagram scroll view in and render the ER-style schema with FK links.
    /// Dragged box positions persist per database via `diagramKey`.
    public func showDiagram() {
        guard let db else { return }
        resultsScroll.isHidden = true
        diagramScroll.isHidden = false
        emptyState.hide()  // a grid's "No Rows" belongs to the grid, not the diagram
        diagramView.load(db, tables: tables, key: diagramKey)
        updateEditAffordances()
        setStatus(
            String(
                localized: "\(tables.count) tables · foreign keys shown as links · drag boxes to arrange, double-click background to reset",
                bundle: .module),
            error: false)
    }

    /// Show the cached query result in the grid and set a status line reflecting
    /// error / rows-affected (writes) / row-count (reads).
    public func showResults() {
        diagramScroll.isHidden = true
        resultsScroll.isHidden = false
        result = lastQueryResult
        rebuildResultColumns()
        // Fresh rows arrive in query order; put them back under the sort the header shows.
        // The preview re-renders on every status tick, so without this a sorted grid would
        // quietly revert to file order every few seconds.
        if let descriptor = resultsTable.sortDescriptors.first { sortResults(by: descriptor) }
        resultsTable.reloadData()
        updateEditAffordances()
        // A read-only browser (Quick Look) says so and never offers the edit hint.
        let readOnly = isReadOnly || (currentURL != nil && !fileIsWritable), editable = editableTable != nil && !isReadOnly
        // A table (or query) with columns and no rows says so, over the grid under its header.
        if result.error == nil, !result.columns.isEmpty, result.rows.isEmpty {
            emptyState.show(
                symbol: "tablecells",
                title: String(localized: "No Rows", bundle: .module, comment: "Database grid: the table or query returned no rows"),
                subtitle: currentTable.map {
                    String(localized: "\($0) is empty.", bundle: .module, comment: "Database grid: the named table has no rows")
                } ?? String(localized: "The query returned no rows.", bundle: .module))
        } else {
            emptyState.hide()
        }
        if let err = result.error {
            setStatus(
                String(
                    localized: "Error: \(err)", bundle: .module,
                    comment: "Database console status; the placeholder is SQLite's error message"),
                error: true)
        } else if result.columns.isEmpty {
            let n = result.rowsAffected
            setStatus(
                readOnly
                    ? String(localized: "OK · \(n) rows affected  ·  read-only", bundle: .module)
                    : String(localized: "OK · \(n) rows affected", bundle: .module), error: false)
        } else {
            let n = result.rows.count
            switch (readOnly, editable) {
            case (false, false): setStatus(String(localized: "\(n) rows", bundle: .module), error: false)
            case (true, false): setStatus(String(localized: "\(n) rows  ·  read-only", bundle: .module), error: false)
            case (false, true): setStatus(String(localized: "\(n) rows · double-click a cell to edit", bundle: .module), error: false)
            case (true, true):
                setStatus(String(localized: "\(n) rows  ·  read-only · double-click a cell to edit", bundle: .module), error: false)
            }
        }
    }

    /// Render the current table's DDL as a synthetic result: one row per column with
    /// PK/FK annotations (FKs shown as `→ table.column`), type and NOT NULL flags.
    public func showStructure() {
        diagramScroll.isHidden = true
        resultsScroll.isHidden = false
        emptyState.hide()  // the structure lists columns, never "No Rows"
        guard let db, let t = currentTable else {
            setStatus(String(localized: "Select a table to see its structure", bundle: .module), error: false); return
        }
        let cols = db.schema(t)
        let fks = db.foreignKeys(t)
        result = SQLiteDB.Result(
            columns: [
                String(localized: "Column", bundle: .module, comment: "Database structure header: the column's name"),
                String(localized: "Type", bundle: .module, comment: "Database structure header: the column's declared type"),
                String(localized: "Key", bundle: .module, comment: "Database structure header: primary/foreign key"),
                String(localized: "Not Null", bundle: .module, comment: "Database structure header: NOT NULL constraint"),
            ],
            rows: cols.map { c in
                var key = c.pk ? "PK" : ""
                if let fk = fks.first(where: { $0.from == c.name }) {
                    let ref = fk.toColumn.isEmpty ? "→ \(fk.toTable)" : "→ \(fk.toTable).\(fk.toColumn)"
                    key = key.isEmpty ? ref : "\(key)  \(ref)"
                }
                return [c.name, c.type.isEmpty ? "—" : c.type, key, c.notNull ? "✓" : ""]
            },
            error: nil, rowsAffected: 0)
        rebuildResultColumns()
        resultsTable.reloadData()
        updateEditAffordances()
        setStatus(
            String(
                localized: "\(cols.count) columns in \(t)", bundle: .module,
                comment: "Database structure status; the placeholder is a table name"),
            error: false)
    }

    /// Save the currently displayed grid (query or structure) to a CSV file via a
    /// save panel; beeps if there's nothing to export.
    @objc public func exportCSV() {
        guard !result.columns.isEmpty else { NSSound.beep(); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = (currentTable ?? "export") + ".csv"
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self else { return }
            // The status line is where every other outcome lands, so a write that fails (a
            // read-only folder, a full disk) is reported there too.
            do {
                try self.resultCSV().write(to: url, atomically: true, encoding: .utf8)
                let n = self.result.rows.count
                self.setStatus(
                    String(
                        localized: "Exported \(n) rows to \(url.lastPathComponent)", bundle: .module,
                        comment: "Database status; the placeholder is a file name"), error: false)
            } catch {
                self.setStatus(String(localized: "Export failed: \(error.localizedDescription)", bundle: .module), error: true)
            }
        }
    }

    /// The displayed grid as CSV text — header row, then every row — for Export CSV.
    /// Its own function so `--selftest-db-grid` can pin the escaping without a save panel.
    public func resultCSV() -> String {
        var csv = result.columns.map(csvEscape).joined(separator: ",") + "\n"
        for row in result.rows { csv += row.map(csvEscape).joined(separator: ",") + "\n" }
        return csv
    }

    /// RFC 4180 CSV field escaping: quote and double-up `"` when the value contains
    /// a comma, quote, or newline.
    private func csvEscape(_ s: String) -> String {
        (s.contains(",") || s.contains("\"") || s.contains("\n"))
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// Tear down and recreate the result grid's columns to match `result.columns`
    /// (called on every result/structure swap since column sets differ).
    public func rebuildResultColumns() {
        // Same column set as before → the sort survives (a status-tick refresh or a cell edit
        // rebuilds the grid for the same table); a different set → the descriptors go, because
        // their keys are positional and "c2 descending" would mean a different column now.
        let sameColumns = resultsTable.tableColumns.map(\.title) == result.columns
        let keptSort = sameColumns ? resultsTable.sortDescriptors : []
        for col in resultsTable.tableColumns { resultsTable.removeTableColumn(col) }
        // Swapped in every rebuild, same as the CSV table (whose recipe this reuses): the
        // header view is recreated with the columns, so theming it once at init would be
        // undone on the next table switch. The VIEW alone is not enough — the stock header
        // CELL paints a system background over it, hence the themed cell below.
        // No columns, no header: an empty header is all filler, which the stock view paints in
        // the system's grey across the whole strip.
        resultsTable.headerView = result.columns.isEmpty ? nil : ThemedTableHeaderView()
        for (i, name) in result.columns.enumerated() {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(i)"))
            col.title = name
            // 6pt: the results cells inset their text that much further than a header cell
            // does, so an uninset title sits left of the column it labels. Measured, not
            // guessed — `--dump-header-paint` prints both and the gap between them.
            col.headerCell = ThemedTableHeaderCell(title: name, titleInset: 6)
            col.width = 160
            col.minWidth = 40
            // Header-click sorting. The keys are POSITIONAL (`c0` is the first column of
            // whatever is showing), so the descriptors are cleared below — carrying "sorted by
            // c2 descending" into a different table would silently sort by a different column.
            col.sortDescriptorPrototype = NSSortDescriptor(key: "c\(i)", ascending: true)
            resultsTable.addTableColumn(col)
        }
        resultsTable.sortDescriptors = keptSort
    }

    /// Header-click sorting for the results grid: reorder the fetched rows IN MEMORY — a re-query
    /// wrapped in `ORDER BY` would change WHICH rows are on screen as well as their order.
    /// `rowIDs` is permuted by the same moves: it maps a grid row to the database row an edit
    /// writes to, and moving one without the other would send an UPDATE to the wrong record.
    public func sortResults(by descriptor: NSSortDescriptor) {
        guard let key = descriptor.key, let index = Int(key.dropFirst()),
            result.columns.indices.contains(index)
        else { return }
        endCellEdit(commit: false)
        let order = CellOrder.permutation(
            of: result.rows, by: index,
            ascending: descriptor.ascending, nullsFirst: true)
        result = SQLiteDB.Result(
            columns: result.columns, rows: order.map { result.rows[$0] },
            error: result.error, rowsAffected: result.rowsAffected)
        if rowIDs.count == order.count { rowIDs = order.map { rowIDs[$0] } }
        resultsTable.reloadData()
    }

    /// Update the status label text, coloring it red on error.
    public func setStatus(_ text: String, error: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = error ? NSColor.systemRed : Theme.statusText
    }
}

// MARK: - The results grid's menu

extension DatabaseView: NSMenuDelegate {
    /// Built per click so it names what it would act on, and offers nothing where a delete
    /// cannot run — a view, a WITHOUT ROWID table, a custom query's grid, a read-only file.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === resultsMenu else { return }
        menu.removeAllItems()
        let rows = rowsForDelete()
        guard editableTable != nil, mode == .results, !rows.isEmpty else { return }
        menu.addItem(
            rows.count == 1
                ? String(localized: "Delete Row", bundle: .module) : String(localized: "Delete \(rows.count) Rows", bundle: .module),
            action: #selector(deleteSelectedRows), target: self, symbol: "trash")
    }
}
