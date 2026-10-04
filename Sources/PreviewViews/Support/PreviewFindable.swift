//
//  PreviewFindable.swift
//  Sidewatch
//
//  A preview surface the find bar FILTERS rather than searches.
//
//  Created by David Sherlock on 9/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit

/// A preview surface the find bar filters rather than searches: matching rows or nodes stay,
/// the rest hide, the bar's count is what is left, ▲ ▼ move the selection through the matches,
/// and dismissing the bar shows everything again.
public protocol PreviewFindable: NSView {
    /// Keeps what matches `text` (everything, for an empty text) and returns the match count.
    @discardableResult
    func filter(_ text: String, caseSensitive: Bool) -> Int
    /// The next or previous match, wrapping.
    func selectMatch(forward: Bool)
}
