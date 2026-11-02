//
//  LogView+Testing.swift
//  PreviewViews
//
//  LogView: the controls and what they show, for a harness that drives them as a person would.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import LogReader
import ThemedControls

extension LogView {
    /// A level's box in the bar, to click.
    public func levelBoxForTesting(_ level: LogLevel) -> NSButton? { levelBoxes[level] }
    /// The Other box (entries with no level).
    public var unleveledBoxForTesting: NSButton { unleveledBox }
    /// The component menu's items, to pick one (`performAction` on the menu).
    public var componentMenuForTesting: NSMenu? { componentButton.menu }
    /// The time menu.
    public var timeMenuForTesting: NSMenu? { timeButton.menu }
    public var componentButtonHiddenForTesting: Bool { componentButton.isHidden }
    public var followBoxForTesting: NSButton { followBox }
    public var tableForTesting: NSTableView { tableView }
    public var detailTextForTesting: String { detailView.string }
    public var summaryTextForTesting: String { summaryLabel.stringValue }
    /// Whether the view has shown the whole file: its own summary, landed on the main thread, says it is complete.
    public var isReadForTesting: Bool { summary?.isComplete == true }
    /// Whether a filter run is still going (or waiting to).
    public var isFilteringForTesting: Bool { filtering || refilterPending }
    /// The entry a row shows.
    public func entryForTesting(row: Int) -> LogEntry? { entryIndex(forRow: row).flatMap { index?.entry(at: $0) } }
    /// A row's cell text, by column id (`time`, `level`, `component`, `message`), as drawn.
    public func cellTextForTesting(row: Int, column: String) -> String? {
        guard let col = tableView.tableColumns.first(where: { $0.identifier.rawValue == column }) else { return nil }
        return (tableView(tableView, viewFor: col, row: row) as? NSTextField)?.stringValue
    }
    /// The colour a row's level is drawn in.
    public func levelColourForTesting(row: Int) -> NSColor? {
        guard let col = tableView.tableColumns.first(where: { $0.identifier.rawValue == "level" }) else { return nil }
        return (tableView(tableView, viewFor: col, row: row) as? NSTextField)?.textColor
    }
    /// The row menu built for `row`, as a right-click on it builds it.
    public func rowMenuForTesting(row: Int) -> NSMenu? {
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        guard let menu = tableView.menu else { return nil }
        menuNeedsUpdate(menu)
        return menu
    }
}
