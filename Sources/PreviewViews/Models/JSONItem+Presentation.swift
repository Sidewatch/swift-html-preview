//
//  JSONItem+Presentation.swift
//  Sidewatch
//
//  How a tree node is drawn: its colour and whether it opens.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit

extension JSONItem {
    /// The colour the node's value is drawn in, by kind.
    public var color: NSColor {
        switch kind {
        case .container: return Theme.statusText
        case .null: return Theme.keyword
        case .bool, .number: return Theme.number
        case .string: return Theme.string
        case .other: return Theme.foreground
        }
    }

    public var isExpandable: Bool { !children.isEmpty }
}
