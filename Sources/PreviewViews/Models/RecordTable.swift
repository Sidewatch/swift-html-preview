//
//  RecordTable.swift
//  Sidewatch
//
//  What the record table shows: columns, rows (and section rows), and the edit each cell and
//  each enable switch writes back into the text.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A line-oriented file as a table, built by `RecordFormat.table(_:)`. Every edit is a function
/// from the document's text to its new text — the format's own line rewrite — so the view
/// never knows the file's syntax.
public nonisolated struct RecordTable: Sendable {
    /// How a column's text is drawn.
    public enum Style: Sendable {
        /// A name: monospaced, medium weight.
        case key
        /// A value: monospaced, the theme's string colour.
        case value
        /// Code or a command: monospaced, foreground.
        case code
        /// Words: the interface font.
        case prose
        /// Several short items drawn as chips (host names).
        case chips
        /// Status tags drawn as tinted chips (`blocked`, `fuzzy`).
        case tags
    }

    /// One column.
    public struct Column: Sendable {
        public let id: String
        public let title: String
        public let width: CGFloat
        public let style: Style
    }

    /// One row: a record, or a section title spanning the table.
    public struct Row: Sendable {
        /// The cells' text, keyed by column id (a missing key is an empty cell).
        public var cells: [String: String]
        /// 1-based line in the file, for the harness and "Copy Line".
        public var line: Int
        /// Set for a section row: the title it shows across the table.
        public var section: String?
        /// Whether the record is on (nil: it cannot be switched off).
        public var enabled: Bool?
        /// A problem worth flagging on the row (a schedule that never runs), shown as its tooltip
        /// and in the warning colour.
        public var warning: String?
        /// The edits this row's cells accept: column id → (text, typed value) → new text.
        public var edits: [String: @Sendable (String, String) -> String] = [:]
        /// The enable switch's edit: (text, on) → new text.
        public var toggle: (@Sendable (String, Bool) -> String)?
    }

    public var columns: [Column]
    public var rows: [Row]
    /// The line above the table: "42 entries · 3 disabled".
    public var summary: String
    /// The empty state's symbol, title and subtitle for a file with no records.
    public var empty: (symbol: String, title: String, subtitle: String)

    /// Whether any row has an enable switch (the table then shows the switch column).
    public var hasToggles: Bool { rows.contains { $0.enabled != nil } }

    /// Each row's cells joined (section rows empty), as written and lowercased — what the find bar
    /// filters. Filled by `preparingSearch()`, where the table is built, so a long file's are made
    /// off the main thread with it; empty until then.
    public var haystacks: [String] = []
    public var lowerHaystacks: [String] = []

    /// What shows while a long file's table is built off the main thread.
    public static var loading: RecordTable {
        RecordTable(
            columns: [], rows: [], summary: String(localized: "Loading…", bundle: .module),
            empty: ("hourglass", String(localized: "Loading…", bundle: .module), ""))
    }

    /// The table with its search text made.
    public func preparingSearch() -> RecordTable {
        var copy = self
        copy.haystacks = rows.map { $0.section == nil ? $0.cells.values.joined(separator: "\u{1}") : "" }
        copy.lowerHaystacks = copy.haystacks.map { $0.lowercased() }
        return copy
    }
}
