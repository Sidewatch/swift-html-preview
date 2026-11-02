//
//  LogView+Find.swift
//  PreviewViews
//
//  LogView: the find bar filters the entries by text, in the background.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import LogReader

extension LogView: PreviewFindable {
    /// Keeps the entries holding `text` (in any of their lines). The search runs in the background: this returns the
    /// count shown now, and `onMatchCount` gives the find bar the real one when it lands.
    @discardableResult
    public func filter(_ text: String, caseSensitive: Bool) -> Int {
        find(text, caseSensitive: caseSensitive, regex: false)
    }

    /// `filter(_:caseSensitive:)` with a regular expression when `regex`.
    @discardableResult
    public func find(_ text: String, caseSensitive: Bool, regex: Bool) -> Int {
        guard text != filter.text || caseSensitive != filter.caseSensitive || regex != filter.isRegex else { return tableView.numberOfRows }
        filter.text = text
        filter.caseSensitive = caseSensitive
        filter.isRegex = regex
        refilter()
        return tableView.numberOfRows
    }

    /// The next or previous entry the text matched, wrapping.
    public func selectMatch(forward: Bool) {
        let rows = tableView.numberOfRows
        guard rows > 0 else { return }
        let current = tableView.selectedRowIndexes.first ?? (forward ? -1 : rows)
        let next = ((current + (forward ? 1 : -1)) % rows + rows) % rows
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }
}
