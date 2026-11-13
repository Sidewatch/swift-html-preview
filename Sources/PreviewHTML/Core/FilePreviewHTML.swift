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

    /// The first ``byteCap`` bytes of the file at `url` (all of a smaller one), whether that cut it
    /// short, and its whole size. Only those bytes are read, however large the file; a cut that
    /// fell inside a UTF-8 character drops that character's first bytes, so the text still reads
    /// as UTF-8 and not, every accent and ideograph of it, as Latin-1.
    public static func readStart(of url: URL) -> (data: Data, truncated: Bool, fileSize: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: byteCap + 1)) ?? Data()
        guard data.count > byteCap else { return (data, false, data.count) }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? data.count
        return (droppingPartialCharacter(atEndOf: data.prefix(byteCap)), true, max(size, data.count))
    }

    /// `data` without the first bytes of a UTF-8 character its end cut through.
    static func droppingPartialCharacter(atEndOf data: Data) -> Data {
        var end = data.endIndex
        var continuation = 0
        while end > data.startIndex, continuation < 3, data[end - 1] & 0xC0 == 0x80 {
            end -= 1
            continuation += 1
        }
        guard end > data.startIndex else { return Data(data) }
        let lead = data[end - 1]
        let length = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
        return length > continuation + 1 ? Data(data[data.startIndex..<(end - 1)]) : Data(data)
    }

    /// The page for `url`, or nil when the file cannot be read or is not something to show as
    /// text. Main actor: the highlighter's static entry is.
    @MainActor public static func render(fileAt url: URL, theme: ThemeSnapshot? = ThemeSnapshot.load()) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        // An empty file reads as nil at once; it is an empty page, not an unreadable file.
        let head = (try? handle.read(upToCount: sniffLength)) ?? Data()
        if DatabasePreviewHTML.isSQLite(head) { return DatabasePreviewHTML.page(databaseAt: url, theme: theme) }
        if ArchiveKind.detect(head: head) != nil { return ArchivePreviewHTML.page(archiveAt: url, theme: theme) }
        if looksBinary(head) { return nil }
        guard let start = readStart(of: url) else { return nil }
        let (slice, truncated, fileSize) = (start.data, start.truncated, start.fileSize)
        guard let text = slice.utf8String ?? String(data: slice, encoding: .isoLatin1) else { return nil }
        let note =
            truncated
            ? String(
                localized: "Showing the first \(byteCap / 1_000_000) MB of \(fileSize / 1_000_000) MB.", bundle: .module,
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
