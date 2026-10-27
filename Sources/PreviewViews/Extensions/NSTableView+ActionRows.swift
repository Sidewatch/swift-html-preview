//
//  NSTableView+ActionRows.swift
//  PreviewViews
//
//  The rows a command from a row's menu, or Edit ▸ Copy, acts on.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit

extension NSTableView {
    /// The rows a command from a row's menu, or Edit ▸ Copy, acts on, in table order: the right-clicked row alone when
    /// it is outside the selection (Finder's rule), else the selection.
    func actionRows() -> [Int] {
        let clicked = clickedRow
        if clicked >= 0, !selectedRowIndexes.contains(clicked) { return [clicked] }
        return selectedRowIndexes.sorted()
    }
}
