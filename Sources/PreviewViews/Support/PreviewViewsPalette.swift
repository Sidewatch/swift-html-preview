//
//  PreviewViewsPalette.swift
//  PreviewViews
//
//  The colours and fonts the preview views draw with, supplied by the host.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import ThemedControls

/// The colours and fonts the preview views draw with, supplied by the host: the app passes its live
/// theme, the Quick Look extension the snapshot the app writes. Read live, so a theme change shows
/// on the next redraw (the views also listen for `PreviewViews.themeDidChange`).
public protocol PreviewViewsPalette: ControlPalette {
    /// The page behind the data: the editor's background.
    var background: NSColor { get }
    /// The cursor colour (a key column's accent in some tables).
    var cursor: NSColor { get }
    /// Syntax colours the trees and tables borrow.
    var property: NSColor { get }
    var string: NSColor { get }
    var number: NSColor { get }
    var keyword: NSColor { get }
    /// The colour of a removed line (a value that failed to save).
    var removed: NSColor { get }
    /// The interface font and its small size.
    var uiFont: NSFont { get }
    var uiFontSmall: NSFont { get }
    /// The editor's monospaced font.
    var editorFont: NSFont { get }
    /// The code preview's gutter: its background and line numbers.
    var gutterBackground: NSColor { get }
    var gutterText: NSColor { get }
}

extension PreviewViewsPalette {
    public var gutterBackground: NSColor { background }
    public var gutterText: NSColor { mutedText }
}

/// The preview views' host-supplied configuration.
public enum PreviewViews {
    /// The palette the views draw with. Set once at launch (the app) or per preview (Quick Look).
    nonisolated(unsafe) public static var palette: PreviewViewsPalette = DefaultPalette()
    /// Posted by the host when its theme changes; the views re-read `palette` and redraw. The app's
    /// own theme notification uses the same name.
    public static let themeDidChange = Notification.Name("Sidewatch.themeDidChange")
    /// The database browser's table-list width the person last dragged to, and where to keep it;
    /// nil storage keeps the default.
    nonisolated(unsafe) public static var savedDatabaseSidebarWidth: () -> CGFloat? = { nil }
    nonisolated(unsafe) public static var saveDatabaseSidebarWidth: (CGFloat) -> Void = { _ in }
}

/// A plain dark palette, for a host that has not set one.
struct DefaultPalette: PreviewViewsPalette {
    var isDark: Bool { true }
    var accent: NSColor { .controlAccentColor }
    var foreground: NSColor { NSColor(white: 0.86, alpha: 1) }
    var selection: NSColor { NSColor(white: 0.3, alpha: 1) }
    var sidebarBackground: NSColor { NSColor(white: 0.1, alpha: 1) }
    var sidebarText: NSColor { NSColor(white: 0.7, alpha: 1) }
    var statusText: NSColor { NSColor(white: 0.6, alpha: 1) }
    var border: NSColor { NSColor(white: 0.2, alpha: 1) }
    var rowSeparator: NSColor { NSColor(white: 0.18, alpha: 1) }
    var mutedText: NSColor { NSColor(white: 0.5, alpha: 1) }
    var statusBackground: NSColor { NSColor(white: 0.09, alpha: 1) }
    var smallFont: NSFont { .systemFont(ofSize: 11) }
    func elevatedSurface(dark: CGFloat, light: CGFloat) -> NSColor { NSColor(white: 0.12 + dark, alpha: 1) }
    var background: NSColor { NSColor(white: 0.12, alpha: 1) }
    var cursor: NSColor { .controlAccentColor }
    var property: NSColor { .systemTeal }
    var string: NSColor { .systemGreen }
    var number: NSColor { .systemOrange }
    var keyword: NSColor { .systemPurple }
    var removed: NSColor { .systemRed }
    var uiFont: NSFont { .systemFont(ofSize: 12) }
    var uiFontSmall: NSFont { .systemFont(ofSize: 11) }
    var editorFont: NSFont { .monospacedSystemFont(ofSize: 12, weight: .regular) }
}

/// The views' own name for the palette, so they read as the app's views did (`Theme.background`).
enum Theme {
    static var background: NSColor { PreviewViews.palette.background }
    static var foreground: NSColor { PreviewViews.palette.foreground }
    static var statusText: NSColor { PreviewViews.palette.statusText }
    static var accent: NSColor { PreviewViews.palette.accent }
    static var border: NSColor { PreviewViews.palette.border }
    static var rowSeparator: NSColor { PreviewViews.palette.rowSeparator }
    static var sidebarBg: NSColor { PreviewViews.palette.sidebarBackground }
    static var sidebarText: NSColor { PreviewViews.palette.sidebarText }
    static var cursor: NSColor { PreviewViews.palette.cursor }
    static var property: NSColor { PreviewViews.palette.property }
    static var string: NSColor { PreviewViews.palette.string }
    static var number: NSColor { PreviewViews.palette.number }
    static var keyword: NSColor { PreviewViews.palette.keyword }
    static var removed: NSColor { PreviewViews.palette.removed }
    static var uiFont: NSFont { PreviewViews.palette.uiFont }
    static var uiFontSmall: NSFont { PreviewViews.palette.uiFontSmall }
    static var editorFont: NSFont { PreviewViews.palette.editorFont }
    static func elevatedSurface(dark: CGFloat = 0.08, light: CGFloat = 0.04) -> NSColor {
        PreviewViews.palette.elevatedSurface(dark: dark, light: light)
    }
}

extension Notification.Name {
    /// The host's theme change (see `PreviewViews.themeDidChange`).
    static let themeDidChange = PreviewViews.themeDidChange
}
