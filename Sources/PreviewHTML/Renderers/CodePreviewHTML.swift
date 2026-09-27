//
//  CodePreviewHTML.swift
//  PreviewHTML
//
//  A source file as a line-numbered, syntax-coloured table.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import CodeHighlighting
import CodeLanguage

/// A source file as a line-numbered table, coloured through `HighlightedHTML` — the editor's
/// three tiers: a tree-sitter grammar (which needs the grammar query bundles beside the running
/// binary — an app extension copies them), the single-file-component splitter, the regex tables
/// (so SCSS, Less, Terraform… are coloured here as they are in the editor).
public enum CodePreviewHTML {
    static let css = """
        table.code { border-collapse: collapse; width: 100%; }
        table.code td { vertical-align: top; padding: 0 12px 0 0; white-space: pre; }
        table.code td.n { text-align: right; color: var(--gutter); user-select: none; padding-left: 12px; width: 1%; }
        table.code td.c { width: 99%; }
        """

    /// The body: the text coloured for `language`, one table row per line.
    @MainActor public static func body(_ text: String, language: Language) -> String {
        let highlighted = HighlightedHTML.render(text, language: language)
        let rows = highlighted.components(separatedBy: "\n").enumerated().map { i, line in
            "<tr><td class=\"n\">\(i + 1)</td><td class=\"c\">\(line.isEmpty ? " " : line)</td></tr>"
        }
        return "<table class=\"code\">\n" + rows.joined(separator: "\n") + "\n</table>"
    }

    /// The whole page for `text` named `title`.
    @MainActor public static func page(title: String, text: String, language: Language, note: String? = nil, theme: ThemeSnapshot?) -> String {
        PreviewPage.page(title: title, body: body(text, language: language), note: note, theme: theme, css: css)
    }
}
