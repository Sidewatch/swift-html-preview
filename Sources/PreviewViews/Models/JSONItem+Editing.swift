//
//  JSONItem+Editing.swift
//  Sidewatch
//
//  What of a tree node can be edited in place, and how typed text maps back to a value.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import DataConverter

extension JSONItem {
    /// Whether the key can be renamed: an object / mapping member the format can rename, never
    /// an index or the root.
    public var keyIsEditable: Bool { if case .key = components.last { return renamable } else { return false } }
    /// Whether the value can be typed over: a scalar.
    public var valueIsEditable: Bool { kind != .container && kind != .other }
    /// The scalar's kind for the encoders, or nil for a container.
    public var scalarKind: StructuredEdit.ScalarKind? {
        switch kind {
        case .string: return .string;
        case .number: return .number;
        case .bool: return .bool;
        case .null: return .null;
        default: return nil
        }
    }
    /// The decoration the KEY cell wears around its bare text: a leaf's trailing colon.
    public var keyDecoration: (prefix: String, suffix: String) { ("", isExpandable ? "" : ":") }
    /// The decoration the VALUE cell wears: a string's quotes, nothing for the other kinds.
    public var valueDecoration: (prefix: String, suffix: String) { kind == .string ? ("\"", "\"") : ("", "") }

    /// What the value cell shows while editing: a string without its quotes, its line breaks as ↵.
    public var editableValueText: String { rawString?.oneLine ?? valueText }
    /// The typed text as the value to write: ↵ back to a line break for a string.
    public func editedValue(_ typed: String) -> String { kind == .string ? typed.replacingOccurrences(of: "↵", with: "\n") : typed }
}
