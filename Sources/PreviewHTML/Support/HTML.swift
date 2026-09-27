//
//  HTML.swift
//  PreviewHTML
//
//  Escaping, the one page every renderer wraps its body in, and the shared bar and filter.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Escaping, the page around a rendered body, and the pieces the data renderers share: a sticky
/// bar (tabs, a filter field, a count) and the script that filters rows as the user types.
/// The page names the file only in its `<title>`: Quick Look's panel already shows the name.
/// Scripts DO run in a Quick Look HTML preview (measured), so the filter is live; the tabs are
/// CSS radio inputs and need no script.
public enum PreviewPage {

    /// The page fetches NOTHING. Quick Look's own web view renders it, and the host app cannot
    /// seal that view the way it seals its own, so a Markdown file holding a remote image would
    /// make a request from Finder. This policy is the seal that travels WITH the page: no remote
    /// image, style, script, font, frame or fetch. The page itself needs only inline styles, one
    /// inline script (the filter) and `data:` images.
    public static let contentSecurityPolicy =
        "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; "
        + "img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; font-src data:; form-action 'none'\">"

    /// HTML-escaped text.
    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// A byte count the way Finder says it.
    public static func byteLabel(_ n: Int) -> String {
        var value = Double(n), unit = 0
        while value >= 1000, unit < 4 { value /= 1000; unit += 1 }
        if unit == 0 { return String(localized: "\(n) bytes", bundle: .module, comment: "Quick Look previews: a size under one kilobyte.") }
        // The number in the locale's digits and decimal mark; the unit's wording is the translation's.
        let v = value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))
        switch unit {
        case 1:  return String(localized: "\(v) KB", bundle: .module, comment: "Quick Look previews: a size in kilobytes, e.g. 2.4 KB")
        case 2:  return String(localized: "\(v) MB", bundle: .module, comment: "Quick Look previews: a size in megabytes, e.g. 2.4 MB")
        case 3:  return String(localized: "\(v) GB", bundle: .module, comment: "Quick Look previews: a size in gigabytes, e.g. 2.4 GB")
        default: return String(localized: "\(v) TB", bundle: .module, comment: "Quick Look previews: a size in terabytes, e.g. 2.4 TB")
        }
    }

    /// A count with thousands separators.
    public static func grouped(_ n: Int) -> String {
        n.formatted()
    }

    /// The bar's height, which the sticky table headers sit under.
    static let barHeight = 34

    /// The page: the theme's page and text colours (paper white and the system greys without
    /// one), the body, an optional note. `css` is a renderer's own rules, appended; `script`
    /// runs after the body.
    public static func page(title: String, body: String, note: String? = nil, theme: ThemeSnapshot?, css: String = "", script: String = "") -> String {
        let bg = theme?.background ?? "#FFFFFF", fg = theme?.foreground ?? "#1D1D1F"
        let stripBg = theme?.statusBackground ?? "#F5F5F7", stripFg = theme?.statusText ?? "#6E6E73"
        let border = theme?.border ?? "#E5E5EA", gutter = theme?.gutterText ?? "#A1A1A6", accent = theme?.accent ?? "#0A84FF"
        let scheme = (theme?.isDark ?? false) ? "dark" : "light"
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>\(escape(title))</title>
        \(contentSecurityPolicy)
        <meta name="color-scheme" content="\(scheme)">
        <style>
        :root { color-scheme: \(scheme); --bg: \(bg); --fg: \(fg); --muted: \(stripFg); --gutter: \(gutter); --border: \(border); --strip: \(stripBg); --accent: \(accent); }
        body { margin: 0; background: var(--bg); color: var(--fg); font: 12px/1.45 ui-monospace, "SF Mono", Menlo, monospace; }
        .note { color: var(--muted); font: 11px -apple-system, system-ui, sans-serif; padding: 8px 12px; }
        \(barCSS)
        \(css)
        </style></head><body>
        \(body)
        \(note.map { "<div class=\"note\">\(escape($0))</div>" } ?? "")
        \(script.isEmpty ? "" : "<script>\(script)</script>")
        </body></html>
        """
    }

    /// The sticky bar: tabs and a filter field on the theme's status colours. Radio inputs
    /// (`input.tab`) are direct children of `<body>` before the bar and the panels, so the
    /// `:checked ~` selectors reach both the label and the panel with no script.
    static let barCSS = """
        .bar { position: sticky; top: 0; z-index: 1; box-sizing: border-box; height: \(barHeight)px; display: flex; align-items: center; gap: 6px; padding: 0 12px; background: var(--strip); color: var(--muted); font: 11px -apple-system, system-ui, sans-serif; border-bottom: 1px solid var(--border); overflow-x: auto; }
        .bar .tabs { display: flex; gap: 2px; flex: 1 1 auto; min-width: 0; overflow-x: auto; }
        .bar label { white-space: nowrap; padding: 3px 9px; border-radius: 6px; cursor: pointer; color: var(--muted); }
        .bar label .n { opacity: 0.7; margin-left: 4px; }
        .bar label:hover { color: var(--fg); }
        input.tab { display: none; }
        input.filter { flex: 0 0 200px; margin-left: auto; box-sizing: border-box; padding: 3px 8px; border: 1px solid var(--border); border-radius: 6px; background: var(--bg); color: var(--fg); font: 12px -apple-system, system-ui, sans-serif; outline: none; }
        input.filter:focus { border-color: var(--accent); }
        .bar .count { white-space: nowrap; }
        .panel { display: none; }
        .meta { padding: 8px 12px 0; color: var(--muted); font: 11px -apple-system, system-ui, sans-serif; }
        .meta .shown { margin-left: 8px; color: var(--fg); }
        """

    /// The filter field for a bar; the count beside it is the caller's `.shown` span.
    static func filterField(placeholder: String) -> String {
        "<input class=\"filter\" type=\"search\" placeholder=\"\(escape(placeholder))\" spellcheck=\"false\" autocomplete=\"off\">"
    }

    /// Filters every `tr.row` on the page by the text typed into `input.filter` (case-folded,
    /// substring), and writes "n of m shown" into each `.shown` beside a filtered table. Esc clears.
    static let filterScript: String = {
        // The script fills `{shown}` and `{total}` in; the words around them come from the catalog.
        let template = String(localized: "\("{shown}") of \("{total}") shown", bundle: .module,
                              comment: "Quick Look table preview: how many rows match the filter, out of all rows; e.g. 3 of 40 shown.")
        let shownTemplate = (try? JSONSerialization.data(withJSONObject: template, options: .fragmentsAllowed))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"{shown} of {total} shown\""
        return """
        (function () {
          var f = document.querySelector('input.filter'); if (!f) return;
          var shownText = \(shownTemplate);
          var tables = Array.prototype.slice.call(document.querySelectorAll('table.data'));
          function apply() {
            var q = f.value.trim().toLowerCase();
            tables.forEach(function (t) {
              var rows = t.querySelectorAll('tr.row'), shown = 0;
              for (var i = 0; i < rows.length; i++) {
                var hit = !q || rows[i].textContent.toLowerCase().indexOf(q) >= 0;
                rows[i].style.display = hit ? '' : 'none'; if (hit) shown++;
              }
              var s = document.getElementById('shown-' + t.id);
              if (s) s.textContent = q ? shownText.replace('{shown}', shown).replace('{total}', rows.length) : '';
            });
          }
          f.addEventListener('input', apply);
          f.addEventListener('keydown', function (e) { if (e.key === 'Escape') { f.value = ''; apply(); } });
        })();
        """
    }()
}
