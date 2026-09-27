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
    public let snapshot: ThemeSnapshot
    public init(_ snapshot: ThemeSnapshot) { self.snapshot = snapshot }
    public func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .comment:   return ThemeSnapshot.color(snapshot.comment)
        case .string:    return ThemeSnapshot.color(snapshot.string)
        case .keyword:   return ThemeSnapshot.color(snapshot.keyword)
        case .type, .attribute: return ThemeSnapshot.color(snapshot.type)
        case .number:    return ThemeSnapshot.color(snapshot.number)
        case .function:  return ThemeSnapshot.color(snapshot.function)
        case .variable:  return ThemeSnapshot.color(snapshot.variable)
        case .property:  return ThemeSnapshot.color(snapshot.property)
        case .added:     return ThemeSnapshot.color(snapshot.added)
        case .removed:   return ThemeSnapshot.color(snapshot.removed)
        }
    }
    public var foreground: NSColor { ThemeSnapshot.color(snapshot.foreground) }
}
