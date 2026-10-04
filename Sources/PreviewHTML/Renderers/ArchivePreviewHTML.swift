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
    static let css =
        TablePreviewHTML.css + """
            table.data td.name { white-space: nowrap; }
            table.data td.name .d { display: inline-block; }
            table.data td.name .tw { display: inline-block; width: 14px; color: var(--muted); }
            table.data tr.folder td.name .tw::before { content: "▾"; }
            table.data tr.folder.closed td.name .tw::before { content: "▸"; }
            table.data tr.folder { cursor: default; }
            table.data tr.folder td.name { font-weight: 600; }
            table.data tr.tree-hidden { display: none; }
            body.filtering table.data tr.tree-hidden { display: table-row; }
            table.data td.size { text-align: right; color: var(--muted); }
            table.data td.when { color: var(--muted); }
            """

    /// The body for `listing`: the bar, then one row per node, folders opened, capped.
    public static func body(listing: ArchiveListing) -> String {
        let files = listing.fileCount, folders = listing.folderCount
        var parts = [
            listing.kind == .zip ? "Zip" : "Tar",
            String(
                localized: "\(files) files", bundle: .module, comment: "Quick Look archive preview bar: how many files the archive holds."),
        ]
        if folders > 0 {
            parts.append(
                String(
                    localized: "\(folders) folders", bundle: .module,
                    comment: "Quick Look archive preview bar: how many folders the archive holds."))
        }
        parts.append(
            String(
                localized: "\(PreviewPage.byteLabel(listing.totalSize)) uncompressed", bundle: .module,
                comment: "Quick Look archive preview bar: the archive's total size once extracted, such as 2.4 MB."))
        let summary = parts.joined(separator: " · ")
        var rows: [String] = []
        let modified = Dictionary(listing.entries.map { ($0.path, $0.modified) }, uniquingKeysWith: { a, _ in a })
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        func walk(_ nodes: [ArchiveNode], depth: Int) {
            for node in nodes {
                guard rows.count < rowCap else { return }
                let when = (modified[node.path] ?? modified[node.path + "/"]).flatMap { $0 }.map { formatter.string(from: $0) } ?? ""
                rows.append(
                    "<tr class=\"row \(node.isDirectory ? "folder" : "file")\" data-p=\"\(PreviewPage.escape(trimmedPath(node.path)))\"><td class=\"name\"><span class=\"d\" style=\"width:\(depth * 16)px\"></span><span class=\"tw\"></span>\(PreviewPage.escape(node.name))<span class=\"path\" hidden>\(PreviewPage.escape(node.path))</span></td>"
                        + "<td class=\"size\">\(node.isDirectory ? PreviewPage.byteLabel(node.size) : PreviewPage.byteLabel(node.size))</td><td class=\"when\">\(PreviewPage.escape(when))</td></tr>"
                )
                if node.isDirectory { walk(node.children, depth: depth + 1) }
            }
        }
        walk(listing.tree, depth: 0)
        var out =
            "<div class=\"bar\"><span class=\"count\">\(PreviewPage.escape(summary))</span><span class=\"meta shown\" id=\"shown-a\"></span>\(PreviewPage.filterField(placeholder: String(localized: "Filter by path", bundle: .module, comment: "Quick Look archive preview: placeholder in the filter field.")))</div>\n"
        if rows.isEmpty {
            return out
                + "<div class=\"note\">\(String(localized: "Empty archive.", bundle: .module, comment: "Quick Look archive preview: the archive holds nothing."))</div>"
        }
        out +=
            "<table class=\"data\" id=\"a\"><thead><tr><th>\(String(localized: "Name", bundle: .module, comment: "Quick Look archive preview: column header for member names."))</th><th>\(String(localized: "Size", bundle: .module, comment: "Quick Look archive preview: column header for member sizes."))</th><th>\(String(localized: "Modified", bundle: .module, comment: "Quick Look archive preview: column header for when each member last changed."))</th></tr></thead><tbody>\n"
            + rows.joined(separator: "\n") + "\n</tbody></table>"
        if rows.count >= rowCap {
            out +=
                "<div class=\"note\">\(String(localized: "First \(rowCap) members.", bundle: .module, comment: "Quick Look archive preview: only this many archive members are listed."))</div>"
        }
        return out
    }

    /// The whole page for the archive at `url`, or nil when it cannot be read.
    public static func page(archiveAt url: URL, theme: ThemeSnapshot?) -> String? {
        guard let listing = try? Archive.listing(at: url) else { return nil }
        return PreviewPage.page(
            title: url.lastPathComponent, body: body(listing: listing), theme: theme, css: css,
            script: PreviewPage.filterScript + "\n" + treeScript)
    }

    /// A member's path without the trailing slash a folder entry carries.
    static func trimmedPath(_ path: String) -> String { path.hasSuffix("/") ? String(path.dropLast()) : path }

    /// Clicking a folder row folds or unfolds it; a member is hidden while any folder above it is
    /// closed. While the filter holds a query, matches inside closed folders still show.
    static let treeScript = """
        (function () {
          var rows = Array.prototype.slice.call(document.querySelectorAll('table.data tr.row'));
          function refresh() {
            var closed = rows.filter(function (r) { return r.classList.contains('closed'); })
              .map(function (r) { return r.getAttribute('data-p') + '/'; });
            rows.forEach(function (r) {
              var p = r.getAttribute('data-p') || '';
              r.classList.toggle('tree-hidden', closed.some(function (c) { return p.indexOf(c) === 0; }));
            });
          }
          rows.forEach(function (r) {
            if (!r.classList.contains('folder')) return;
            r.addEventListener('click', function () { r.classList.toggle('closed'); refresh(); });
          });
          var f = document.querySelector('input.filter');
          if (f) f.addEventListener('input', function () { document.body.classList.toggle('filtering', f.value.trim() !== ''); });
        })();
        """
}
