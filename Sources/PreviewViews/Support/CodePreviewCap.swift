//
//  CodePreviewCap.swift
//  PreviewViews
//
//  The line cap a code preview lays out, so a huge source shows its start at once.
//
//  Created by David Sherlock on 10/10/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A code preview lays out at most `lineCap` lines: TextKit builds every glyph of a text view's
/// storage before the first draw, and a 100,000-line source holds the main thread for tens of
/// seconds. The preview is a look, not an editor, so the text past the cap is left out and a
/// note says how much there was.
nonisolated public enum CodePreviewCap {
    /// Lines laid out; the rest are counted, not shown.
    public static let lineCap = 10_000

    /// `text` cut after `lineCap` lines, with the line total and whether anything was cut.
    public static func cut(_ text: String, lineCap: Int = lineCap) -> (text: String, totalLines: Int, cut: Bool) {
        let utf16 = text.utf16
        var lines = 1
        var cutIndex: String.UTF16View.Index?
        var i = utf16.startIndex
        while i < utf16.endIndex {
            if utf16[i] == 0x0A {
                lines += 1
                if lines > lineCap, cutIndex == nil { cutIndex = i }
            }
            i = utf16.index(after: i)
        }
        guard let cutIndex, let end = String.Index(cutIndex, within: text) else { return (text, lines, false) }
        return (String(text[..<end]), lines, true)
    }
}
