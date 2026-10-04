//
//  NativePreview.swift
//  PreviewViews
//
//  The native, read-only preview of a file: the view the app shows it in, chosen the way the
//  HTML page chooses.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import ArchiveIndex
import CodeLanguage
import FoundationExtensions
import PreviewHTML
import ThemedControls
import CodeHighlighting

/// The native, read-only preview of a file — the same view the app shows it in — for the Quick Look
/// extension (and the app's harness, which proves the extension's route through this one function).
/// Decided by content first (a SQLite header, an archive signature, NUL bytes), then by name and
/// language. Markdown is not native: it needs the web page (Mermaid, LaTeX), so it answers nil, as
/// does a binary or unreadable file.
public enum NativePreview {
    /// Which view a file got.
    public enum Kind: String, Sendable {
        case database, archive, table, tree, records, code
    }

    /// A made preview: its kind and its view.
    public struct Made {
        public let kind: Kind
        public let view: NSView
    }

    /// The preview of the file at `url`, or nil for Markdown, a binary file, or one that cannot be read.
    public static func make(fileAt url: URL) -> Made? {
        guard let handle = try? FileHandle(forReadingFrom: url), let head = try? handle.read(upToCount: 512) else { return nil }
        try? handle.close()
        if DatabasePreviewHTML.isSQLite(head) {
            return Made(kind: .database, view: DatabasePreviewView(url: url))
        }
        if ArchiveKind.detect(head: head) != nil {
            let view = ZipArchiveView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
            view.load(url: url)
            return Made(kind: .archive, view: view)
        }
        if FilePreviewHTML.looksBinary(head) { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let truncated = data.count > FilePreviewHTML.byteCap
        let slice = truncated ? data.prefix(FilePreviewHTML.byteCap) : data[...]
        guard let text = Data(slice).utf8String ?? String(data: slice, encoding: .isoLatin1) else { return nil }
        let name = url.lastPathComponent
        let ext = url.lowercasedExtension
        if ["md", "markdown", "mdx"].contains(ext) { return nil }
        let language = Language.detect(filename: name)
        if ["csv", "tsv", "tab"].contains(ext) {
            let view = CSVTableView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
            view.isReadOnly = true
            view.load(text)
            return Made(kind: .table, view: view)
        }
        if let format = RecordFormat.of(url: url, language: language) {
            let view = RecordTableView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
            view.isReadOnly = true
            view.load(format.table(text).preparingSearch())
            return Made(kind: .records, view: view)
        }
        if let format = TreeFormat.of(url: url, language: language) {
            let view = JSONTreeView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
            view.isReadOnly = true
            if format == .json {
                view.load(text, lenient: TreeFormat.readsLeniently(language))
            } else {
                let value = format.value(of: text, bytes: { try? Data(contentsOf: url) })
                view.load(structured: value, format: format.name, keepingExpansion: false, renamesKey: format.renamesKey)
            }
            return Made(kind: .tree, view: view)
        }
        let note =
            truncated
            ? String(
                localized: "Showing the first \(FilePreviewHTML.byteCap / 1_000_000) MB of \(data.count / 1_000_000) MB.", bundle: .module,
                comment: "Quick Look code preview: the file is too large, so only its start is shown; both values are whole megabytes.")
            : nil
        return Made(kind: .code, view: CodePreviewView(text: text, language: language, note: note))
    }

    /// Puts the theme snapshot's colours on the preview views, the themed controls and the
    /// highlighter — what the Quick Look extension does before it makes a preview.
    public static func wear(_ snapshot: ThemeSnapshot) {
        let palette = SnapshotPalette(snapshot)
        PreviewViews.palette = palette
        ThemedControls.palette = palette
        HighlightTheme.colors = SnapshotColors(snapshot)
    }
}
