//
//  ArchivePreviewHTML.swift
//  PreviewHTML
//
//  A zip or tar as its tree of members — without unpacking it — filtered live.
//
//  Created by David Sherlock on 9/24/26.
//

import Foundation
import ArchiveIndex

/// An archive as the tree of what is inside it, read from its directory through swift-archive-
/// index (the app's own archive preview, brought to Quick Look — David, 24 Sep 2026: "we could
/// also add zip previewing like we have"): folders first, each level indented, a file's size
/// and time, the bar counting files and folders and holding the filter, which matches a member's
/// whole path. Nothing is extracted.
public enum ArchivePreviewHTML {
    public static let rowCap = 2_000
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
        var summary = "\(listing.kind == .zip ? "Zip" : "Tar") · \(PreviewPage.grouped(files)) file\(files == 1 ? "" : "s")"
        if folders > 0 { summary += " · \(PreviewPage.grouped(folders)) folder\(folders == 1 ? "" : "s")" }
        summary += " · \(PreviewPage.byteLabel(listing.totalSize)) uncompressed"
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
        var out = "<div class=\"bar\"><span class=\"count\">\(PreviewPage.escape(summary))</span><span class=\"meta shown\" id=\"shown-a\"></span>\(PreviewPage.filterField(placeholder: "Filter by path"))</div>\n"
        if rows.isEmpty { return out + "<div class=\"note\">Empty archive.</div>" }
        out += "<table class=\"data\" id=\"a\"><thead><tr><th>Name</th><th>Size</th><th>Modified</th></tr></thead><tbody>\n" + rows.joined(separator: "\n") + "\n</tbody></table>"
        if rows.count >= rowCap { out += "<div class=\"note\">First \(PreviewPage.grouped(rowCap)) members.</div>" }
        return out
    }

    /// The whole page for the archive at `url`, or nil when it cannot be read.
    public static func page(archiveAt url: URL, theme: ThemeSnapshot?) -> String? {
        guard let listing = try? Archive.listing(at: url) else { return nil }
        return PreviewPage.page(title: url.lastPathComponent, body: body(listing: listing), theme: theme, css: css, script: PreviewPage.filterScript)
    }
}
