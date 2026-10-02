//
//  SnapshotColors.swift
//  PreviewHTML
//
//  The highlighter's colours from a theme snapshot.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import CodeHighlighting

/// The highlighter's colours from a snapshot — installed on `HighlightTheme.colors` before the
/// extension renders, so the spans carry the theme's hexes.
public struct SnapshotColors: TokenColorProviding {
    /// The theme the colours come from.
    public let snapshot: ThemeSnapshot
    /// Colours read from `snapshot`.
    public init(_ snapshot: ThemeSnapshot) { self.snapshot = snapshot }
    /// The snapshot's colour for a token kind; attributes share the type colour.
    public func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .comment: return ThemeSnapshot.color(snapshot.comment)
        case .string: return ThemeSnapshot.color(snapshot.string)
        case .keyword: return ThemeSnapshot.color(snapshot.keyword)
        case .type, .attribute: return ThemeSnapshot.color(snapshot.type)
        case .number: return ThemeSnapshot.color(snapshot.number)
        case .function: return ThemeSnapshot.color(snapshot.function)
        case .variable: return ThemeSnapshot.color(snapshot.variable)
        case .property: return ThemeSnapshot.color(snapshot.property)
        case .identifier: return ThemeSnapshot.color(snapshot.identifier ?? snapshot.foreground)
        case .added: return ThemeSnapshot.color(snapshot.added)
        case .removed: return ThemeSnapshot.color(snapshot.removed)
        }
    }
    /// Plain text: the snapshot's foreground.
    public var foreground: NSColor { ThemeSnapshot.color(snapshot.foreground) }
}
