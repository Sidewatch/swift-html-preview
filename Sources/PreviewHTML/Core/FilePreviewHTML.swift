//
//  FilePreviewHTML.swift
//  PreviewHTML
//
//  One entry: a file on disk to the HTML page a preview extension answers with.
//
//  Created by David Sherlock on 9/24/26.
//

import Foundation
import CodeLanguage

/// A file as the HTML page a data-based Quick Look preview answers with (24 Sep 2026, extracted
/// from Sidewatch's extension): a SQLite database (by its header, whatever its name) as its
/// tables; CSV and TSV as a table; Markdown rendered; everything else as line-numbered, coloured
/// source. Text is read UTF-8-else-Latin-1 and capped — Quick Look is a glance, not the editor.
/// `theme` is the host app's snapshot (the default reads the file the host writes); nil renders
/// on a paper page.
public enum FilePreviewHTML {
    /// Past this the preview shows the first part and says so.
    public static let byteCap = 1_000_000

    /// The page for `url`, or nil when the file cannot be read. Main actor: the highlighter's
    /// static entry is.
    @MainActor public static func render(fileAt url: URL, theme: ThemeSnapshot? = ThemeSnapshot.load()) -> String? {
        guard let head = try? FileHandle(forReadingFrom: url).read(upToCount: 16), let full = try? Data(contentsOf: url) else { return nil }
        if DatabasePreviewHTML.isSQLite(head) { return DatabasePreviewHTML.page(databaseAt: url, theme: theme) }
        let truncated = full.count > byteCap
        let slice = truncated ? full.prefix(byteCap) : full[...]
        guard let text = String(data: slice, encoding: .utf8) ?? String(data: slice, encoding: .isoLatin1) else { return nil }
        let note = truncated ? "Showing the first \(byteCap / 1_000_000) MB of \(full.count / 1_000_000) MB." : nil
        let name = url.lastPathComponent
        switch (name as NSString).pathExtension.lowercased() {
        case "csv": return TablePreviewHTML.page(title: name, text: text, tabSeparated: false, theme: theme)
        case "tsv", "tab": return TablePreviewHTML.page(title: name, text: text, tabSeparated: true, theme: theme)
        case "md", "markdown", "mdx":
            let previous = HighlightThemeSwap.install(theme)
            defer { HighlightThemeSwap.restore(previous) }
            return MarkdownPreviewHTML.page(title: name, markdown: text, note: note, theme: theme)
        default:
            let previous = HighlightThemeSwap.install(theme)
            defer { HighlightThemeSwap.restore(previous) }
            return CodePreviewHTML.page(title: name, text: text, language: Language.detect(filename: name), note: note, theme: theme)
        }
    }
}
