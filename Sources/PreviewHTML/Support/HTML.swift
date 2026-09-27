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
///
/// The page names the file only in its `<title>` — Quick Look's own panel already shows the
/// name, and a strip repeating it cost a line of every preview (David, 24 Sep 2026: "remove the
/// title thing, the quick view already shows the filename"). Scripts DO run in a Quick Look
/// HTML preview (measured 24 Sep 2026: a page whose script spun for four seconds cost the
/// WebContent process Quick Look spawned for it four seconds of CPU), so the filter is live;
/// the tabs are CSS radio inputs and need no script at all.
public enum PreviewPage {

    /// The page fetches NOTHING (26 Sep 2026). A preview extension's HTML is rendered by Quick
    /// Look's own web view, which the host app cannot seal the way it seals its own — Sidewatch's
    /// Markdown view runs with JavaScript off behind a block-all-network content rule list, and
    /// none of that reaches this page. So a Markdown file holding `![](https://tracker/pixel.png)`
    /// would have made a request from Finder, in an app whose whole claim is that it talks to
    /// nobody. This policy is the seal that travels WITH the page: no remote image, style,
    /// script, font, frame or fetch, whatever the file being previewed contains. Inline styles
    /// and one inline script are all the page itself uses (the tab radios are pure CSS; the
    /// filter field is the script), and images only ever arrive as `data:` URIs.
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
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var value = Double(n), unit = 0
        while value >= 1000, unit < units.count - 1 { value /= 1000; unit += 1 }
        if unit == 0 { return "\(n) \(n == 1 ? "byte" : "bytes")" }
        return String(format: value < 10 ? "%.1f %@" : "%.0f %@", value, units[unit])
    }

    /// A count with thousands separators.
    public static func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_US_POSIX"); f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
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

    /// The filter field and its count, for a bar.
    static func filterField(placeholder: String) -> String {
        "<input class=\"filter\" type=\"search\" placeholder=\"\(escape(placeholder))\" spellcheck=\"false\" autocomplete=\"off\">"
    }

    /// Filters every `tr.row` on the page by the text typed into `input.filter` (case-folded,
    /// substring), and writes "n of m shown" into each `.shown` beside a filtered table. Esc clears.
    static let filterScript = """
        (function () {
          var f = document.querySelector('input.filter'); if (!f) return;
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
              if (s) s.textContent = q ? shown + ' of ' + rows.length + ' shown' : '';
            });
          }
          f.addEventListener('input', apply);
          f.addEventListener('keydown', function (e) { if (e.key === 'Escape') { f.value = ''; apply(); } });
        })();
        """
}
