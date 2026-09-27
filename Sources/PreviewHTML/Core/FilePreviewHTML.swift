//
//  FilePreviewHTML.swift
//  PreviewHTML
//
//  One entry: a file on disk to the HTML page a preview extension answers with.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import CodeLanguage
import ArchiveIndex
import FoundationExtensions

/// A file as the HTML page a data-based Quick Look preview answers with, decided by the BYTES
/// first: a SQLite header → its tables; a zip or tar signature → its member tree; a NUL in the
/// first block → nothing (an MPEG-2 stream shares TypeScript's `.ts`). Then by extension: CSV and
/// TSV as a table, Markdown rendered, everything else as coloured source. Text is read
/// UTF-8-else-Latin-1 and capped. `theme` is the host's snapshot; nil renders on a paper page.
public enum FilePreviewHTML {
    /// Past this the preview shows the first part and says so.
    public static let byteCap = 1_000_000
    /// How much of the file decides whether it is text at all.
    static let sniffLength = 512

    /// Whether `head` (a file's first bytes) is binary: a NUL byte in the first block. UTF-16
    /// text trips this too, which is right — the page decodes UTF-8 and Latin-1 only.
    public static func looksBinary(_ head: Data) -> Bool { head.prefix(sniffLength).contains(0) }

    /// The page for `url`, or nil when the file cannot be read or is not something to show as
    /// text. Main actor: the highlighter's static entry is.
    @MainActor public static func render(fileAt url: URL, theme: ThemeSnapshot? = ThemeSnapshot.load()) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url), let head = try? handle.read(upToCount: sniffLength) else { return nil }
        if DatabasePreviewHTML.isSQLite(head) { return DatabasePreviewHTML.page(databaseAt: url, theme: theme) }
        if ArchiveKind.detect(head: head) != nil { return ArchivePreviewHTML.page(archiveAt: url, theme: theme) }
        if looksBinary(head) { return nil }
        guard let full = try? Data(contentsOf: url) else { return nil }
        let truncated = full.count > byteCap
        let slice = truncated ? full.prefix(byteCap) : full[...]
        guard let text = Data(slice).utf8String ?? String(data: slice, encoding: .isoLatin1) else { return nil }
        let note =
            truncated
            ? String(
                localized: "Showing the first \(byteCap / 1_000_000) MB of \(full.count / 1_000_000) MB.", bundle: .module,
                comment: "Quick Look text preview: the file is too large, so only its start is shown; both values are whole megabytes.")
            : nil
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
