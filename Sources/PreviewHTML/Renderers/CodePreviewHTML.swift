//
//  CodePreviewHTML.swift
//  PreviewHTML
//
//  A source file as a line-numbered, syntax-coloured table.
//
//  Created by David Sherlock on 9/24/26.
//

import Foundation
import CodeHighlighting
import CodeLanguage

/// A source file as a line-numbered table, coloured through the tree-sitter highlighter's HTML
/// output (which needs the grammar query bundles beside the running binary — an app extension
/// copies them) or escaped plainly when no grammar applies.
public enum CodePreviewHTML {
    static let css = """
        table.code { border-collapse: collapse; width: 100%; }
        table.code td { vertical-align: top; padding: 0 12px 0 0; white-space: pre; }
        table.code td.n { text-align: right; color: var(--gutter); user-select: none; padding-left: 12px; width: 1%; }
        table.code td.c { width: 99%; }
        """

    /// The body: the text coloured for `language` (or escaped), one table row per line.
    @MainActor public static func body(_ text: String, language: Language) -> String {
        let highlighted = TreeSitterHighlighter.highlightedHTML(text, language: language) ?? PreviewPage.escape(text)
        let rows = highlighted.components(separatedBy: "\n").enumerated().map { i, line in
            "<tr><td class=\"n\">\(i + 1)</td><td class=\"c\">\(line.isEmpty ? " " : line)</td></tr>"
        }
        return "<table class=\"code\">\n" + rows.joined(separator: "\n") + "\n</table>"
    }

    /// The whole page for `text` named `title`.
    @MainActor public static func page(title: String, text: String, language: Language, note: String? = nil, theme: ThemeSnapshot?) -> String {
        PreviewPage.page(title: title, kind: language.displayName, body: body(text, language: language), note: note, theme: theme, css: css)
    }
}
