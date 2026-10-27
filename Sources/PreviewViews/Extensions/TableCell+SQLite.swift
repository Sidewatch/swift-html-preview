//
//  TableCell+SQLite.swift
//  PreviewViews
//
//  A database cell as a table cell for copying.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import DataConverter
import SQLiteReader

extension TableCell {
    /// `cell` as a table cell: the same value, the same type.
    init(_ cell: SQLiteDB.Cell) {
        switch cell {
        case .null: self = .null
        case .integer(let value): self = .integer(value)
        case .real(let value): self = .real(value)
        case .text(let text): self = .text(text)
        case .blob(let bytes, let count): self = .blob(bytes, count: count)
        }
    }
}
