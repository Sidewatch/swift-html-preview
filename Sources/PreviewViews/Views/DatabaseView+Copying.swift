//
//  DatabaseView+Copying.swift
//  PreviewViews
//
//  What the database view copies: grid rows in every format, a table's name and the SQL that made it.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import AppKitViews
import DataConverter
import FoundationExtensions
import SQLiteReader
import ThemedControls

extension DatabaseView {
    /// Points the grid's copy items at what the grid shows: its columns, the typed cells of the rows a command acts
    /// on, the right-clicked cell.
    func wireCopier() {
        copier.host = self
        copier.columns = { [unowned self] in self.result.columns }
        copier.rows = { [unowned self] in self.actionCells().map { $0.map(TableCell.init) } }
        copier.clickedCell = { [unowned self] in
            let row = self.resultsTable.clickedRow
            guard let column = self.modelColumn(ofDisplayColumn: self.resultsTable.clickedColumn) else { return nil }
            return self.result.cells[safe: row]?[safe: column].map(TableCell.init)
        }
        copier.insertTable = { [unowned self] in self.mode == .results ? self.browsedTable : nil }
        copier.insertStatements = { [unowned self] table in self.insertStatements(into: table) }
    }

    /// The typed cells of the rows a command acts on (``NSTableView/actionRows()``), in grid order.
    func actionCells() -> [[SQLiteDB.Cell]] {
        resultsTable.actionRows().compactMap { result.cells[safe: $0] }
    }

    /// The grid column at `displayColumn` (columns can be dragged into another order) as an index into
    /// `result.columns`: the model index its `c<i>` identifier carries.
    func modelColumn(ofDisplayColumn displayColumn: Int) -> Int? {
        guard resultsTable.tableColumns.indices.contains(displayColumn) else { return nil }
        return Int(resultsTable.tableColumns[displayColumn].identifier.rawValue.dropFirst())
    }

    /// The rows a command acts on as INSERT statements into `table`.
    func insertStatements(into table: String) -> String {
        SQLiteDB.insertStatements(into: table, columns: result.columns, rows: actionCells())
    }

    /// A table's own menu, for a box in the diagram.
    func tableMenu(for table: String) -> NSMenu {
        let menu = NSMenu()
        addTableItems(for: table, to: menu)
        return menu
    }

    /// Copy Name and, when SQLite keeps the SQL that made it, Copy CREATE Statement — what an agent asked about a table
    /// needs first.
    func addTableItems(for table: String, to menu: NSMenu) {
        menu.addItem(
            String(localized: "Copy Name", bundle: .module), action: #selector(copyTableName(_:)), target: self, represented: table)
        guard db?.createStatements(for: table).isEmpty == false else { return }
        menu.addItem(
            String(localized: "Copy CREATE Statement", bundle: .module), action: #selector(copyCreateStatement(_:)), target: self,
            represented: table)
    }

    @objc func copyTableName(_ sender: NSMenuItem) {
        guard let table = sender.representedObject as? String else { return }
        NSPasteboard.general.copyAndConfirm(table, receipt: String(localized: "Copied name", bundle: .module), in: window)
    }

    @objc func copyCreateStatement(_ sender: NSMenuItem) {
        guard let table = sender.representedObject as? String, let sql = db?.createStatements(for: table), !sql.isEmpty else { return }
        NSPasteboard.general.copyAndConfirm(
            sql.joined(separator: "\n\n") + "\n", receipt: String(localized: "Copied CREATE statement", bundle: .module), in: window)
    }

    /// Edit ▸ Copy: with the tables list in front, the selected table's name; else the grid's selected rows as
    /// tab-separated text. Beeps when there is nothing to copy.
    @objc public func copy(_ sender: Any?) {
        if window?.firstResponder === tableList {
            guard tables.indices.contains(tableList.selectedRow) else { NSSound.beep(); return }
            NSPasteboard.general.copy(tables[tableList.selectedRow])
            return
        }
        if !copier.copySelection() { NSSound.beep() }
    }
}
