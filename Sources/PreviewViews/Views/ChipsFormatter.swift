//
//  ChipsFormatter.swift
//  Sidewatch
//
//  Draws a cell's space-separated items as chips while the field editor still edits plain text.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit

/// A cell's space-separated items drawn as chips — each item on a tinted background, a gap
/// between them — while editing loads the plain text. A formatter, because a cell's decoration
/// must survive into the field editor untouched (swapping the string when editing begins never
/// reaches it).
public nonisolated final class ChipsFormatter: Formatter, @unchecked Sendable {
    private let font: NSFont
    private let text: NSColor
    private let fill: NSColor

    public init(font: NSFont, text: NSColor, fill: NSColor) {
        self.font = font; self.text = text; self.fill = fill
        super.init()
    }
    public required init?(coder: NSCoder) { nil }

    public override func string(for obj: Any?) -> String? { obj as? String }
    public override func editingString(for obj: Any?) -> String? { obj as? String }
    public override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        obj?.pointee = string as NSString
        return true
    }

    /// Each item padded by a thin space on either side inside its tint, items two spaces apart.
    public override func attributedString(for obj: Any, withDefaultAttributes attrs: [NSAttributedString.Key: Any]? = nil)
        -> NSAttributedString?
    {
        guard let value = obj as? String else { return nil }
        let out = NSMutableAttributedString()
        let items = value.split(separator: " ").map(String.init)
        for (i, item) in items.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "  ", attributes: [.font: font])) }
            out.append(
                NSAttributedString(
                    string: "\u{2009}\(item)\u{2009}", attributes: [.font: font, .foregroundColor: text, .backgroundColor: fill]))
        }
        return out
    }
}
