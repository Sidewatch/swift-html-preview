//
//  MarkdownPreviewHTML.swift
//  PreviewHTML
//
//  Markdown rendered, its fenced code coloured, in the theme's colours.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import MarkdownHTML
import CodeHighlighting
import CodeLanguage

/// Markdown rendered through `MarkdownHTML` (GitHub's shape: frontmatter aside, tables, task
/// lists, math as MathML), fenced code coloured through the editor's three highlight tiers, on
/// the theme's page. Mermaid fences stay as their source: the diagram library is the app's, not
/// the extension's.
public enum MarkdownPreviewHTML {
    /// The article's rules: width, headings, code, quotes, tables, links.
    static let css = """
        article { max-width: 820px; margin: 0 auto; padding: 12px 20px 40px; font: 14px/1.55 -apple-system, system-ui, sans-serif; }
        article h1, article h2 { border-bottom: 1px solid var(--border); padding-bottom: 4px; }
        article pre { background: var(--strip); border: 1px solid var(--border); border-radius: 6px; padding: 10px 12px; overflow-x: auto; font: 12px/1.45 ui-monospace, "SF Mono", Menlo, monospace; }
        article code { font: 0.92em ui-monospace, "SF Mono", Menlo, monospace; background: var(--strip); border-radius: 4px; padding: 1px 4px; }
        article pre code { background: none; padding: 0; }
        article blockquote { border-left: 3px solid var(--border); margin: 0; padding: 0 12px; color: var(--muted); }
        article table { border-collapse: collapse; } article th, article td { border: 1px solid var(--border); padding: 4px 8px; }
        article a { color: var(--accent); } article img { max-width: 100%; }
        article hr { border: 0; border-top: 1px solid var(--border); }
        """

    /// The body: the rendered document inside an `<article>`.
    @MainActor public static func body(_ markdown: String) -> String {
        let html = MarkdownHTML.render(
            markdown,
            highlightCode: { code, lang in
                HighlightedHTML.render(code, language: Language.detect(filename: "block." + lang))
            })
        return "<article>\n" + html + "\n</article>"
    }

    /// The whole page for `markdown` named `title`.
    @MainActor public static func page(title: String, markdown: String, note: String? = nil, theme: ThemeSnapshot?) -> String {
        PreviewPage.page(title: title, body: body(markdown), note: note, theme: theme, css: css)
    }
}
