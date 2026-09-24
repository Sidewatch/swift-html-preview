//
//  ThemeSnapshot.swift
//  PreviewHTML
//
//  The app's current theme as a small JSON file the sandboxed Quick Look extension can read,
//  and the token colours built from it.
//
//  Created by David Sherlock on 9/24/26.
//

import AppKit
import CodeHighlighting

/// A host app's current theme, as a sandboxed preview extension sees it (24 Sep 2026, Sidewatch's
/// Quick Look preview: "it's not honouring the theme we picked"). The extension is sandboxed: it cannot read the
/// app's preferences or its theme files, and it has no idea what "Beacon" is. So the APP writes
/// this snapshot — resolved hex colours, nothing to look up — to
/// `~/Library/Application Support/Sidewatch/quicklook-theme.json` at launch and on every theme
/// change, and the extension's entitlements let it read that one folder. Custom and imported
/// themes work the same way, because what is written is the resolved colours.
public struct ThemeSnapshot: Codable, Equatable, Sendable {
    public var name: String
    public var isDark: Bool
    public var background: String
    public var foreground: String
    public var comment: String
    public var string: String
    public var keyword: String
    public var type: String
    public var number: String
    public var function: String
    public var variable: String
    public var property: String
    public var accent: String
    public var gutterText: String
    public var statusBackground: String
    public var statusText: String
    public var border: String
    public var added: String
    public var removed: String

    public init(name: String, isDark: Bool, background: String, foreground: String, comment: String, string: String, keyword: String,
                type: String, number: String, function: String, variable: String, property: String, accent: String, gutterText: String,
                statusBackground: String, statusText: String, border: String, added: String, removed: String) {
        self.name = name; self.isDark = isDark; self.background = background; self.foreground = foreground; self.comment = comment
        self.string = string; self.keyword = keyword; self.type = type; self.number = number; self.function = function
        self.variable = variable; self.property = property; self.accent = accent; self.gutterText = gutterText
        self.statusBackground = statusBackground; self.statusText = statusText; self.border = border; self.added = added; self.removed = removed
    }

    /// Where the app writes it and the extension reads it — under the REAL home, which inside
    /// the sandbox is not `NSHomeDirectory()` (that is the container) but the passwd entry.
    public static var defaultURL: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Sidewatch/quicklook-theme.json")
    }

    public static func load(from url: URL = defaultURL) -> ThemeSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ThemeSnapshot.self, from: data)
    }

    public func write(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// `#RRGGBB` for a colour, in sRGB.
    public static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
    static func color(_ hex: String) -> NSColor {
        var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return .labelColor }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
