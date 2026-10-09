//
//  DatabaseView+Actions.swift
//  Sidewatch
//
//  DatabaseView: Actions.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import SQLiteReader
import UniformTypeIdentifiers
import FoundationExtensions

extension DatabaseView {
    // MARK: - Actions

    /// Sidebar selection changed — load the clicked table.
    @objc public func tableClicked() {
        let row = tableList.selectedRow
        guard tables.indices.contains(row) else { return }
        selectTable(tables[row])
    }

    /// Populate the editor with a `SELECT * LIMIT 200` for the table and show its
    /// canonical (cell-editable where possible) grid. Preserves Structure mode
    /// across the switch.
    public func selectTable(_ table: String) {
        endCellEdit(commit: true)
        currentTable = table
        queryView.string = canonicalSQL(for: table)
        // A schema SOURCE has no rows — clicking a table shows what the file actually says
        // about it, its columns, not an empty result set.
        let wasStructure = mode == .structure || showsSchemaSource
        runCanonicalQuery(for: table)
        mode = .results
        showResults()
        if wasStructure { mode = .structure; showStructure() }
    }

    /// The query the sidebar writes into the editor for `table` — running exactly
    /// this text routes back through the editable canonical path.
    private func canonicalSQL(for table: String) -> String {
        "SELECT * FROM \(SQLiteDB.quoteIdentifier(table)) LIMIT \(Self.canonicalLimit);"
    }

    /// Execute the editor's SQL against the open DB and show the result grid. Caches
    /// the outcome in `lastQueryResult` so mode toggles can restore it without re-running.
    /// SQL matching the canonical table query keeps the grid cell-editable; anything
    /// else produces a plain read-only result grid.
    @objc public func runQuery() {
        guard db != nil else { return }
        endCellEdit(commit: true)
        let sql = queryView.string.trimmed
        guard !sql.isEmpty else { return }
        if let t = currentTable, sql == canonicalSQL(for: t) {
            runCanonicalQuery(for: t)
        } else {
            guard allowsRunning(sql), let connection = db else { return }
            clearEditableGrid()
            lastQueryResult = connection.run(sql)
        }
        mode = .results
        showResults()
    }

    /// Whether a typed script may run now. A read runs on the browsing connection; a write
    /// needs the read-write one (`ensureWritable`); a statement that can lose data is confirmed
    /// first, as Delete Row is.
    private func allowsRunning(_ sql: String) -> Bool {
        let kind = SQLStatementKind.of(script: sql)
        guard kind != .read else { return true }
        if kind == .destructive, !DatabaseView.confirmWrite(SQLStatementKind.summary(of: sql)) { return false }
        return ensureWritable()
    }

    /// Fetch `table`'s canonical grid. For an editable table the fetch selects
    /// `rowid` alongside every column (`SELECT rowid, * … LIMIT 200`) so each grid
    /// row can be targeted by `UPDATE … WHERE rowid = ?`; the rowid column is
    /// stripped from the display into the parallel `rowIDs`. Non-editable objects
    /// (views, WITHOUT ROWID tables, read-only/in-memory databases) fall back to a
    /// plain read-only fetch and raise the "read-only" tooltip hint.
    public func runCanonicalQuery(for table: String) {
        guard let db else { return }
        clearEditableGrid()
        if isTableEditable(table) {
            let r = db.run("SELECT rowid, * FROM \(SQLiteDB.quoteIdentifier(table)) LIMIT \(Self.canonicalLimit)")
            // EVERY rowid must parse, or the grid stays read-only. A sentinel
            // (-1) would be bound into `UPDATE … WHERE rowid = ?` and either
            // silently match nothing or hit an unrelated row — no edit is far
            // better than an edit aimed at the wrong row.
            let ids = r.rows.map { Int64($0.first ?? "") }
            if r.error == nil, r.columns.count > 1, !ids.contains(where: { $0 == nil }) {
                editableTable = table
                rowIDs = ids.compactMap { $0 }
                lastQueryResult = SQLiteDB.Result(
                    columns: Array(r.columns.dropFirst()),
                    rows: r.rows.map { Array($0.dropFirst()) },
                    error: nil, rowsAffected: 0)
                return
            }
        }
        gridReadOnlyHint = true
        lastQueryResult = db.run(canonicalSQL(for: table))
    }

    /// True when `table` can take rowid-targeted writes: a real table (not a view)
    /// with a rowid (not WITHOUT ROWID), on a writable on-disk file (in-memory
    /// schema previews are display-only — nothing would persist). The connection
    /// is read-only until the first write, so the FILE decides, not the connection.
    private func isTableEditable(_ table: String) -> Bool {
        guard let db, !isReadOnly, fileIsWritable else { return false }
        let kind = db.execute(
            "SELECT type FROM sqlite_master WHERE type IN ('table','view') AND name = ?",
            parameters: [.text(table)])
        guard kind.rows.first?.first == "table" else { return false }
        // A user column named rowid/oid/_rowid_ SHADOWS the true rowid: the probe
        // below would resolve to it and succeed, and `SELECT rowid, *` would then
        // hand back that column's values as if they were rowids.
        let shadowed = Set(["rowid", "oid", "_rowid_"])
        guard !db.schema(table).contains(where: { shadowed.contains($0.name.lowercased()) }) else { return false }
        // WITHOUT ROWID tables have no rowid to target — probe with a zero-row select.
        return db.run("SELECT rowid FROM \(SQLiteDB.quoteIdentifier(table)) LIMIT 0").error == nil
    }
}
