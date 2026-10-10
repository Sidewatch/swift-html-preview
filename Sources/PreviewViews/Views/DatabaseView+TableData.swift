//
//  DatabaseView+TableData.swift
//  Sidewatch
//
//  DatabaseView: Table data.
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

extension DatabaseView {
    // MARK: - Table data

    /// Shared data source for both grids: sidebar shows tables, results grid shows rows.
    public func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === tableList ? tables.count : result.rows.count
    }

    /// Header-click sorting for the results grid. The table owns the descriptors and draws the
    /// indicator; this reorders the rows behind them. The sidebar's table list is not sortable,
    /// so it is guarded out.
    public func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard tableView === resultsTable, let descriptor = tableView.sortDescriptors.first else { return }
        sortResults(by: descriptor)
    }

    /// Themed zebra striping for the results grid (the sidebar stays flat) — real rows
    /// alternate with a subtle theme tint, and because it's applied per-row the empty
    /// area below the last row stays the plain themed background instead of grey bars.
    public func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        guard tableView === resultsTable else { return }
        rowView.backgroundColor =
            row % 2 == 0
            ? Theme.background
            : Theme.elevatedSurface(dark: 0.04, light: 0.03)
    }

    /// The theme's selection, not AppKit's accent blue: the cells keep their own colours on it.
    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let accentBar: CGFloat = tableView === tableList ? 3 : 0
        return tableView.reusableView { ThemedPlainRowView(accentBar: accentBar) }
    }

    /// Build a cell for either grid: sidebar cells pair a table name with its row count;
    /// result cells are monospaced, dimming `NULL` values. Column index is parsed from
    /// the `c<i>` identifier set in `rebuildResultColumns`.
    public func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        if tableView === tableList {
            let t = tables[safe: row] ?? ""
            let cell = NSTableCellView()
            // A VIEW is not a table: no rowid, no editing, and its count is a query's result.
            // The list holds both, so it says which.
            let isView = viewNames.contains(t)
            let glyph = NSImageView(
                image: NSImage(
                    systemSymbolName: isView ? "eye" : "tablecells",
                    accessibilityDescription: isView
                        ? String(localized: "View", bundle: .module, comment: "A database view (as opposed to a table)")
                        : String(localized: "Table", bundle: .module, comment: "A database table")) ?? NSImage())
            glyph.contentTintColor = Theme.statusText
            glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            cell.addSubviewsForAutoLayout(glyph)
            cell.toolTip =
                isView
                ? String(
                    localized: "\(t) — a view (read-only)", bundle: .module,
                    comment: "Tooltip on a database view in the table list; the placeholder is its name") : t
            let name = NSTextField.label(t, font: Theme.uiFont, color: Theme.sidebarText, lineBreak: .byTruncatingTail)
            // A schema source's counts are all zero — the file describes tables, it holds no
            // rows — so the column says nothing and is left off.
            let count = NSTextField.label(
                showsSchemaSource ? "" : (tableCounts[t].map { $0.grouped } ?? ""),
                font: Theme.uiFontSmall, color: Theme.statusText, alignment: .right)
            count.setContentCompressionResistancePriority(.required, for: .horizontal)
            cell.addSubviewsForAutoLayout(name, count)
            NSLayoutConstraint.activate([
                glyph.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                glyph.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                glyph.widthAnchor.constraint(equalToConstant: 13),
                name.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 6),
                name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                count.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 6),
                count.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                count.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
        guard let column, let idx = Int(column.identifier.rawValue.dropFirst()),
            let r = result.rows[safe: row], let value = r[safe: idx]
        else { return nil }
        let cell = makeCell(tableView, id: "r")
        cell.textField?.stringValue = value
        cell.textField?.textColor = value == "NULL" ? Theme.statusText : Theme.foreground
        cell.textField?.font = NSFont.mono(11)
        cell.textField?.lineBreakMode = .byTruncatingTail
        return cell
    }

    /// Dequeue (or lazily build) a reusable single-text-field cell for the results grid.
    private func makeCell(_ tableView: NSTableView, id: String) -> NSTableCellView {
        let ident = NSUserInterfaceItemIdentifier(id)
        if let reused = tableView.makeView(withIdentifier: ident, owner: self) as? NSTableCellView { return reused }
        let cell = NSTableCellView()
        cell.identifier = ident
        let tf = NSTextField(labelWithString: "")
        cell.addSubviewsForAutoLayout(tf)
        cell.textField = tf
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
