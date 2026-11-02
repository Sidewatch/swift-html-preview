//
//  LogView+Table.swift
//  PreviewViews
//
//  LogView: the rows, read from the file as they are drawn, and the selected entry in full.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import AppKitViews
import DataConverter
import LogReader
import ThemedControls

extension LogView: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { visible?.count ?? index?.entryCount ?? 0 }

    /// The entry a row shows.
    func entryIndex(forRow row: Int) -> Int? {
        guard row >= 0 else { return nil }
        if let visible { return visible.indices.contains(row) ? visible[row] : nil }
        return row
    }

    /// The row an entry is on, while it is shown.
    func row(forEntry entry: Int) -> Int? {
        guard let visible else { return entry < (index?.entryCount ?? 0) ? entry : nil }
        var lo = 0, hi = visible.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if visible[mid] == entry { return mid }
            if visible[mid] < entry { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView.reusableView { ThemedSelectionRowView(accentBar: 3) }
    }

    public func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let id = column?.identifier, let i = entryIndex(forRow: row), let entry = index?.entry(at: i) else { return nil }
        let field = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? Self.cell(id)
        switch id.rawValue {
        case "time":
            field.stringValue = entry.time.map(LogTimeText.text) ?? "—"
            field.textColor = Theme.statusText
        case "level":
            field.stringValue = entry.level.map(Self.levelCode) ?? ""
            field.textColor = Self.levelColour(entry.level)
        case "component":
            field.stringValue = entry.component ?? ""
            field.textColor = Theme.statusText
        default:
            field.attributedStringValue = messageCell(entry)
        }
        return field
    }

    private static func cell(_ id: NSUserInterfaceItemIdentifier) -> NSTextField {
        let field = NSTextField.label(
            "", font: Theme.editorFont.withSize(max(10, Theme.editorFont.pointSize - 1)), lineBreak: .byTruncatingTail)
        field.identifier = id
        field.cell?.truncatesLastVisibleLine = true
        field.maximumNumberOfLines = 1
        return field
    }

    /// The message, and how many more lines the entry has, muted.
    private func messageCell(_ entry: LogEntry) -> NSAttributedString {
        let font = Theme.editorFont.withSize(max(10, Theme.editorFont.pointSize - 1))
        let quiet = entry.level == .debug || entry.level == .trace
        let text = NSMutableAttributedString(
            string: message(of: entry), attributes: [.font: font, .foregroundColor: quiet ? Theme.mutedText : Theme.foreground])
        if entry.lineCount > 1 {
            let more = String(
                localized: "  +\(entry.lineCount - 1) lines", bundle: .module,
                comment: "Log view: how many more lines an entry has (a stack trace)")
            text.append(NSAttributedString(string: more, attributes: [.font: font, .foregroundColor: Theme.mutedText]))
        }
        return text
    }

    /// An entry's message: a structured line's own, else its first line from where the header ends.
    func message(of entry: LogEntry) -> String {
        let first = firstLine(of: entry)
        if let message = first.head?.message { return message }
        let start = first.head?.messageStart ?? 0
        return String(decoding: first.text.utf8.dropFirst(start), as: UTF8.self)
    }

    /// An entry's first line and header, from the cache while it stays near the screen.
    func firstLine(of entry: LogEntry) -> (text: String, head: LogLineHead?) {
        if let hit = rowCache[entry.index] { return hit }
        guard let index else { return ("", nil) }
        if rowCache.count > 4000 { rowCache.removeAll(keepingCapacity: true) }
        let read = index.firstLine(of: entry)
        rowCache[entry.index] = read
        return read
    }

    public func tableViewSelectionDidChange(_ notification: Notification) { showSelectedEntry() }

    /// The first selected entry in full below the table: every line of it, a JSON line pretty-printed.
    func showSelectedEntry() {
        guard let row = tableView.selectedRowIndexes.first, let i = entryIndex(forRow: row), let entry = index?.entry(at: i), let index
        else {
            detailView.string = ""
            return
        }
        var text = index.text(of: entry, limit: 256 << 10)
        if entry.format == .json, let pretty = JSONStructure.value(of: text)?.jsonText() { text = pretty }
        if entry.format == .dockerJSON, let carried = firstLine(of: entry).head?.message { text = carried }
        detailView.string = text
        detailView.textColor = Theme.foreground
        detailView.scrollToBeginningOfDocument(nil)
    }

    /// The selected entries, in order.
    var selectedEntries: [LogEntry] {
        tableView.selectedRowIndexes.compactMap { entryIndex(forRow: $0) }.compactMap { index?.entry(at: $0) }
    }
}
