//
//  SnapshotPalette.swift
//  PreviewViews
//
//  The preview views' palette read from the theme snapshot the app writes.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import PreviewHTML

/// The preview views' palette read from the theme snapshot the app writes — what the Quick Look
/// extension draws with, since it cannot read the app's preferences. A colour the snapshot does not
/// carry (one written before it was added) is derived from the ones it does.
public struct SnapshotPalette: PreviewViewsPalette {
    /// The snapshot the colours come from.
    public let snapshot: ThemeSnapshot

    /// The palette of `snapshot`.
    public init(_ snapshot: ThemeSnapshot) { self.snapshot = snapshot }

    private func c(_ hex: String?) -> NSColor? { hex.map(ThemeSnapshot.color) }

    public var isDark: Bool { snapshot.isDark }
    public var accent: NSColor { ThemeSnapshot.color(snapshot.accent) }
    public var foreground: NSColor { ThemeSnapshot.color(snapshot.foreground) }
    public var selection: NSColor { c(snapshot.selection) ?? accent.withAlphaComponent(0.25) }
    public var sidebarBackground: NSColor { c(snapshot.sidebarBackground) ?? ThemeSnapshot.color(snapshot.statusBackground) }
    public var sidebarText: NSColor { ThemeSnapshot.color(snapshot.statusText) }
    public var statusText: NSColor { ThemeSnapshot.color(snapshot.statusText) }
    public var border: NSColor { ThemeSnapshot.color(snapshot.border) }
    public var rowSeparator: NSColor { c(snapshot.rowSeparator) ?? ThemeSnapshot.color(snapshot.border) }
    public var mutedText: NSColor { ThemeSnapshot.color(snapshot.gutterText) }
    public var statusBackground: NSColor { ThemeSnapshot.color(snapshot.statusBackground) }
    public var smallFont: NSFont { .systemFont(ofSize: 11) }
    public func elevatedSurface(dark: CGFloat, light: CGFloat) -> NSColor {
        background.blended(withFraction: isDark ? dark : light, of: isDark ? .white : .black) ?? background
    }
    public var background: NSColor { ThemeSnapshot.color(snapshot.background) }
    public var cursor: NSColor { accent }
    public var property: NSColor { ThemeSnapshot.color(snapshot.property) }
    public var string: NSColor { ThemeSnapshot.color(snapshot.string) }
    public var number: NSColor { ThemeSnapshot.color(snapshot.number) }
    public var keyword: NSColor { ThemeSnapshot.color(snapshot.keyword) }
    public var removed: NSColor { ThemeSnapshot.color(snapshot.removed) }
    public var uiFont: NSFont { .systemFont(ofSize: 12) }
    public var uiFontSmall: NSFont { .systemFont(ofSize: 11) }
    public var editorFont: NSFont {
        let size = CGFloat(snapshot.editorFontSize ?? 12)
        return snapshot.editorFontName.flatMap { NSFont(name: $0, size: size) } ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
    /// The gutter's background and numbers.
    public var gutterBackground: NSColor { c(snapshot.gutterBackground) ?? background }
    public var gutterText: NSColor { ThemeSnapshot.color(snapshot.gutterText) }
}
