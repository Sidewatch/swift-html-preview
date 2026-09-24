//
//  HTML.swift
//  PreviewHTML
//
//  Escaping and the one page every renderer wraps its body in.
//
//  Created by David Sherlock on 9/24/26.
//

import Foundation

/// Escaping and the page around a rendered body.
public enum PreviewPage {
    /// HTML-escaped text.
    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The page: the theme's page and text colours (paper white and the system greys without
    /// one), a sticky strip naming the file and its kind, the body, an optional note. `css` is
    /// a renderer's own rules, appended.
    public static func page(title: String, kind: String, body: String, note: String? = nil, theme: ThemeSnapshot?, css: String = "") -> String {
        let bg = theme?.background ?? "#FFFFFF", fg = theme?.foreground ?? "#1D1D1F"
        let stripBg = theme?.statusBackground ?? "#F5F5F7", stripFg = theme?.statusText ?? "#6E6E73"
        let border = theme?.border ?? "#E5E5EA", gutter = theme?.gutterText ?? "#A1A1A6", accent = theme?.accent ?? "#0A84FF"
        let scheme = (theme?.isDark ?? false) ? "dark" : "light"
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>\(escape(title))</title>
        <meta name="color-scheme" content="\(scheme)">
        <style>
        :root { color-scheme: \(scheme); --bg: \(bg); --fg: \(fg); --muted: \(stripFg); --gutter: \(gutter); --border: \(border); --strip: \(stripBg); --accent: \(accent); }
        body { margin: 0; background: var(--bg); color: var(--fg); font: 12px/1.45 ui-monospace, "SF Mono", Menlo, monospace; }
        .strip { position: sticky; top: 0; background: var(--strip); color: var(--muted); font: 11px -apple-system, system-ui, sans-serif; padding: 6px 12px; border-bottom: 1px solid var(--border); z-index: 1; }
        .strip b { color: var(--fg); font-weight: 600; }
        .note { color: var(--muted); font: 11px -apple-system, system-ui, sans-serif; padding: 8px 12px; }
        \(css)
        </style></head><body>
        <div class="strip"><b>\(escape(title))</b> · \(escape(kind))</div>
        \(body)
        \(note.map { "<div class=\"note\">\(escape($0))</div>" } ?? "")
        </body></html>
        """
    }
}
