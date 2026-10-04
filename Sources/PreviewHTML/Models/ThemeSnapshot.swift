//
//  ThemeSnapshot.swift
//  PreviewHTML
//
//  The app's current theme as a small JSON file the sandboxed Quick Look extension can read,
//  and the token colours built from it.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import AppKitViews

/// A host app's current theme, as a sandboxed preview extension sees it. The extension cannot
/// read the app's preferences or theme files, so the APP writes this snapshot — resolved hex
/// colours, nothing to look up — to ``defaultURL`` at launch and on every theme change, and the
/// extension's entitlements let it read that one folder. Custom themes work the same way.
public struct ThemeSnapshot: Codable, Equatable, Sendable {
    /// The theme's display name.
    public var name: String
    /// Whether the theme is dark, which sets the page's `color-scheme`.
    public var isDark: Bool
    /// The page background, `#RRGGBB`.
    public var background: String
    /// The body text colour.
    public var foreground: String
    /// The colour of comment tokens.
    public var comment: String
    /// The colour of string tokens.
    public var string: String
    /// The colour of keyword tokens.
    public var keyword: String
    /// The colour of type and attribute tokens.
    public var type: String
    /// The colour of number tokens.
    public var number: String
    /// The colour of function tokens.
    public var function: String
    /// The colour of variable tokens.
    public var variable: String
    /// The colour of property tokens.
    public var property: String
    /// The colour of plain names; nil (a snapshot written before it existed) paints them as plain text.
    public var identifier: String?
    /// The link and focus colour.
    public var accent: String
    /// The line-number colour.
    public var gutterText: String
    /// The sticky bar's and code blocks' background.
    public var statusBackground: String
    /// Muted text: headers, sizes, quotes, the bar's labels.
    public var statusText: String
    /// Table rules and dividers.
    public var border: String
    /// The colour of added-line tokens in a diff.
    public var added: String
    /// The colour of removed-line tokens in a diff.
    public var removed: String
    /// The selection, the sidebar, the rules between rows and the gutter (nil in a snapshot written
    /// before they were added: the native previews derive them).
    public var selection: String?
    public var sidebarBackground: String?
    public var rowSeparator: String?
    public var gutterBackground: String?
    /// The editor's font (PostScript name) and size, so a native code preview reads like the editor.
    public var editorFontName: String?
    public var editorFontSize: Double?

    /// A snapshot from resolved `#RRGGBB` colours.
    public init(
        name: String, isDark: Bool, background: String, foreground: String, comment: String, string: String, keyword: String,
        type: String, number: String, function: String, variable: String, property: String, accent: String, gutterText: String,
        statusBackground: String, statusText: String, border: String, added: String, removed: String,
        identifier: String? = nil, selection: String? = nil, sidebarBackground: String? = nil, rowSeparator: String? = nil,
        gutterBackground: String? = nil, editorFontName: String? = nil, editorFontSize: Double? = nil
    ) {
        self.name = name; self.isDark = isDark; self.background = background; self.foreground = foreground; self.comment = comment
        self.string = string; self.keyword = keyword; self.type = type; self.number = number; self.function = function
        self.variable = variable; self.property = property; self.accent = accent; self.gutterText = gutterText
        self.statusBackground = statusBackground; self.statusText = statusText; self.border = border; self.added = added;
        self.removed = removed; self.identifier = identifier
        self.selection = selection; self.sidebarBackground = sidebarBackground; self.rowSeparator = rowSeparator
        self.gutterBackground = gutterBackground; self.editorFontName = editorFontName; self.editorFontSize = editorFontSize
    }

    /// Where the app writes it and the extension reads it — under the REAL home, which inside
    /// the sandbox is not `NSHomeDirectory()` (that is the container) but the passwd entry.
    public static var defaultURL: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Sidewatch/quicklook-theme.json")
    }

    /// The snapshot at `url`, or nil when there is none or it does not decode.
    public static func load(from url: URL = defaultURL) -> ThemeSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ThemeSnapshot.self, from: data)
    }

    /// Writes the snapshot as JSON to `url` atomically, creating its folder.
    public func write(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// The colour for a snapshot's hex; the label colour when it does not parse.
    public static func color(_ hex: String) -> NSColor { NSColor(hex: hex) ?? .labelColor }
}
