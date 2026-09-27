//
//  ArchivePreviewHTML.swift
//  PreviewHTML
//
//  A zip or tar as its tree of members — without unpacking it — filtered live.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import ArchiveIndex
import FoundationExtensions

/// An archive as the tree of what is inside it, read from its directory through swift-archive-
/// index: folders first, each level indented, a file's size and time, the bar counting files and
/// folders and holding the filter, which matches a member's whole path. Nothing is extracted.
public enum ArchivePreviewHTML {
    /// The most member rows the page lists; the rest are counted, not shown.
    public static let rowCap = 2_000
    /// The table rules plus the tree's indentation and folder weight.
    static let css = TablePreviewHTML.css + """
        table.data td.name { white-space: nowrap; }
        table.data td.name .d { display: inline-block; }
        table.data tr.folder td.name { font-weight: 600; }
        table.data tr.folder td.name::before { content: "▸"; color: var(--muted); display: inline-block; width: 12px; }
        table.data tr.file td.name::before { content: ""; display: inline-block; width: 12px; }
        table.data td.size { text-align: right; color: var(--muted); }
        table.data td.when { color: var(--muted); }
        """

    /// The body for `listing`: the bar, then one row per node, folders opened, capped.
    public static func body(listing: ArchiveListing) -> String {
        let files = listing.fileCount, folders = listing.folderCount
        var parts = [listing.kind == .zip ? "Zip" : "Tar",
                     String(localized: "\(files) files", bundle: .module, comment: "Quick Look archive preview bar: how many files the archive holds.")]
        if folders > 0 {
            parts.append(String(localized: "\(folders) folders", bundle: .module, comment: "Quick Look archive preview bar: how many folders the archive holds."))
        }
        parts.append(String(localized: "\(PreviewPage.byteLabel(listing.totalSize)) uncompressed", bundle: .module,
                            comment: "Quick Look archive preview bar: the archive's total size once extracted, such as 2.4 MB."))
        let summary = parts.joined(separator: " · ")
        var rows: [String] = []
        let modified = Dictionary(listing.entries.map { ($0.path, $0.modified) }, uniquingKeysWith: { a, _ in a })
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        func walk(_ nodes: [ArchiveNode], depth: Int) {
            for node in nodes {
                guard rows.count < rowCap else { return }
                let when = (modified[node.path] ?? modified[node.path + "/"]).flatMap { $0 }.map { formatter.string(from: $0) } ?? ""
                rows.append("<tr class=\"row \(node.isDirectory ? "folder" : "file")\"><td class=\"name\"><span class=\"d\" style=\"width:\(depth * 16)px\"></span>\(PreviewPage.escape(node.name))<span class=\"path\" hidden>\(PreviewPage.escape(node.path))</span></td>"
                            + "<td class=\"size\">\(node.isDirectory ? PreviewPage.byteLabel(node.size) : PreviewPage.byteLabel(node.size))</td><td class=\"when\">\(PreviewPage.escape(when))</td></tr>")
                if node.isDirectory { walk(node.children, depth: depth + 1) }
            }
        }
        walk(listing.tree, depth: 0)
        var out = "<div class=\"bar\"><span class=\"count\">\(PreviewPage.escape(summary))</span><span class=\"meta shown\" id=\"shown-a\"></span>\(PreviewPage.filterField(placeholder: String(localized: "Filter by path", bundle: .module, comment: "Quick Look archive preview: placeholder in the filter field.")))</div>\n"
        if rows.isEmpty { return out + "<div class=\"note\">\(String(localized: "Empty archive.", bundle: .module, comment: "Quick Look archive preview: the archive holds nothing."))</div>" }
        out += "<table class=\"data\" id=\"a\"><thead><tr><th>\(String(localized: "Name", bundle: .module, comment: "Quick Look archive preview: column header for member names."))</th><th>\(String(localized: "Size", bundle: .module, comment: "Quick Look archive preview: column header for member sizes."))</th><th>\(String(localized: "Modified", bundle: .module, comment: "Quick Look archive preview: column header for when each member last changed."))</th></tr></thead><tbody>\n" + rows.joined(separator: "\n") + "\n</tbody></table>"
        if rows.count >= rowCap { out += "<div class=\"note\">\(String(localized: "First \(rowCap) members.", bundle: .module, comment: "Quick Look archive preview: only this many archive members are listed."))</div>" }
        return out
    }

    /// The whole page for the archive at `url`, or nil when it cannot be read.
    public static func page(archiveAt url: URL, theme: ThemeSnapshot?) -> String? {
        guard let listing = try? Archive.listing(at: url) else { return nil }
        return PreviewPage.page(title: url.lastPathComponent, body: body(listing: listing), theme: theme, css: css, script: PreviewPage.filterScript)
    }
}
