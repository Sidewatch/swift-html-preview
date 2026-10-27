//
//  TableCopier.swift
//  PreviewViews
//
//  The copy items every preview table offers, on a row's menu and as Edit ▸ Copy.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import AppKitViews
import DataConverter
import ThemedControls

/// What a preview table copies, the same in every table: Copy Row (the rows as tab-separated text, what a spreadsheet
/// pastes, and what Edit ▸ Copy copies), Copy Cell, Copy as JSON, Copy as CSV, Copy as Markdown Table, and Copy as SQL
/// INSERT where the table has a name to insert into. A copy from the menu says so in a heads-up; ⌘C stays silent, as
/// it does everywhere. The table says what its columns and rows are; the formats are `TableText`'s.
final class TableCopier: NSObject {
    /// The column names, in order.
    var columns: () -> [String] = { [] }
    /// The cells of the rows a command acts on (``NSTableView/actionRows()``), in table order.
    var rows: () -> [[TableCell]] = { [] }
    /// The right-clicked cell, when the click landed on one.
    var clickedCell: () -> TableCell? = { nil }
    /// The table the rows can be inserted into, when there is one (a browsed table, not a view or a query's result);
    /// nil leaves Copy as SQL INSERT out.
    var insertTable: () -> String? = { nil }
    /// The rows as INSERT statements into the named table.
    var insertStatements: (String) -> String = { _ in "" }
    /// The view whose window shows the heads-up.
    weak var host: NSView?

    /// Appends the copy items for `rowCount` rows to `menu`; nothing for none.
    func addItems(to menu: NSMenu, rowCount: Int) {
        guard rowCount > 0 else { return }
        menu.addItem(
            rowCount == 1 ? String(localized: "Copy Row", bundle: .module) : String(localized: "Copy \(rowCount) Rows", bundle: .module),
            action: #selector(copyRowsFromMenu), target: self, symbol: "doc.on.doc")
        if clickedCell() != nil {
            menu.addItem(String(localized: "Copy Cell", bundle: .module), action: #selector(copyCell), target: self)
        }
        menu.addItem(String(localized: "Copy as JSON", bundle: .module), action: #selector(copyJSON), target: self)
        menu.addItem(String(localized: "Copy as CSV", bundle: .module), action: #selector(copyCSV), target: self)
        menu.addItem(String(localized: "Copy as Markdown Table", bundle: .module), action: #selector(copyMarkdown), target: self)
        if insertTable() != nil {
            menu.addItem(String(localized: "Copy as SQL INSERT", bundle: .module), action: #selector(copyInserts), target: self)
        }
    }

    /// What an item copies.
    enum Format { case rows, cell, json, csv, markdown, sqlInsert }

    /// The text `format` copies now: nil when it has nothing to copy (no rows, no clicked cell, no table to insert
    /// into).
    func text(_ format: Format) -> String? {
        if format == .cell { return clickedCell().map(TableText.plain) }
        if format == .sqlInsert { return insertTable().map(insertStatements) }
        let rows = rows()
        guard !rows.isEmpty else { return nil }
        switch format {
        case .rows: return TableText.tsv(columns: columns(), rows: rows)
        case .json: return TableText.json(columns: columns(), rows: rows)
        case .csv: return TableText.csv(columns: columns(), rows: rows)
        default: return TableText.markdown(columns: columns(), rows: rows)
        }
    }

    /// Edit ▸ Copy over the table: the selected rows as tab-separated text, silently. False when no row is selected.
    @discardableResult
    func copySelection() -> Bool {
        guard let text = text(.rows) else { return false }
        return NSPasteboard.general.copy(text)
    }

    @objc private func copyRowsFromMenu() {
        let count = rows().count
        confirm(
            .rows,
            count == 1 ? String(localized: "Copied row", bundle: .module) : String(localized: "Copied \(count) rows", bundle: .module))
    }

    @objc private func copyCell() { confirm(.cell, String(localized: "Copied cell", bundle: .module)) }
    @objc private func copyJSON() { confirm(.json, String(localized: "Copied as JSON", bundle: .module)) }
    @objc private func copyCSV() { confirm(.csv, String(localized: "Copied as CSV", bundle: .module)) }
    @objc private func copyMarkdown() { confirm(.markdown, String(localized: "Copied as a Markdown table", bundle: .module)) }
    @objc private func copyInserts() { confirm(.sqlInsert, String(localized: "Copied as SQL INSERT", bundle: .module)) }

    /// Puts what `format` copies on the clipboard and says `receipt` over the host's window.
    private func confirm(_ format: Format, _ receipt: String) {
        guard let text = text(format) else { return }
        NSPasteboard.general.copyAndConfirm(text, receipt: receipt, in: host?.window)
    }
}
