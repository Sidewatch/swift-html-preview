//
//  DatabasePreviewHTML.swift
//  PreviewHTML
//
//  A SQLite database as its tables: columns, row counts, the first rows of each.
//
//  Created by David Sherlock on 9/24/26.
//

import Foundation
import SQLiteReader

/// A SQLite database as its tables — each table's columns with their declared types and keys,
/// its row count, and its first rows — read-only through `SQLiteDB`. A file is a SQLite
/// database when it begins with the 16-byte header `SQLite format 3\0`, whatever its name.
public enum DatabasePreviewHTML {
    public static let rowsPerTable = 25
    public static let tableCap = 40
    static let magic = Data("SQLite format 3\u{0}".utf8)

    /// Whether `data` (its first bytes) is a SQLite file.
    public static func isSQLite(_ data: Data) -> Bool { data.count >= magic.count && data.prefix(magic.count) == magic }

    /// The body: one section per table.
    public static func body(databaseAt url: URL) -> String? {
        guard let db = SQLiteDB(url: url) else { return nil }
        let tables = db.tables()
        if tables.isEmpty { return "<div class=\"note\">No tables.</div>" }
        var out = ""
        for table in tables.prefix(tableCap) {
            let columns = db.schema(table)
            let count = db.rowCount(table)
            out += "<section class=\"table\"><h2>\(PreviewPage.escape(table)) <span class=\"count\">\(count) row\(count == 1 ? "" : "s")</span></h2>\n"
            out += "<div class=\"columns\">" + columns.map { c in
                "<span class=\"col\">\(c.pk ? "🔑 " : "")\(PreviewPage.escape(c.name)) <i>\(PreviewPage.escape(c.type.isEmpty ? "any" : c.type))\(c.notNull ? " not null" : "")</i></span>"
            }.joined(separator: " ") + "</div>\n"
            let result = db.run("SELECT * FROM \(SQLiteDB.quoteIdentifier(table)) LIMIT \(rowsPerTable)", limit: rowsPerTable)
            if !result.rows.isEmpty {
                out += "<table class=\"data\"><thead><tr>" + result.columns.map { "<th>\(PreviewPage.escape($0))</th>" }.joined() + "</tr></thead><tbody>\n"
                for row in result.rows { out += "<tr>" + row.map { "<td>\(PreviewPage.escape($0))</td>" }.joined() + "</tr>\n" }
                out += "</tbody></table>\n"
                if count > rowsPerTable { out += "<div class=\"note\">First \(rowsPerTable) of \(count) rows.</div>" }
            }
            out += "</section>\n"
        }
        if tables.count > tableCap { out += "<div class=\"note\">\(tables.count - tableCap) more tables.</div>" }
        return out
    }

    static let css = TablePreviewHTML.css + """
        section.table { padding: 4px 0 8px; }
        h2 { font: 600 13px -apple-system, system-ui, sans-serif; margin: 12px 12px 4px; }
        h2 .count { color: var(--muted); font-weight: 400; margin-left: 6px; }
        .columns { padding: 0 12px 6px; color: var(--muted); font: 11px -apple-system, system-ui, sans-serif; }
        .col { margin-right: 10px; white-space: nowrap; }
        .col i { color: var(--gutter); font-style: normal; }
        """

    /// The whole page for the database at `url`, or nil when it cannot be opened.
    public static func page(databaseAt url: URL, theme: ThemeSnapshot?) -> String? {
        guard let body = body(databaseAt: url), let db = SQLiteDB(url: url) else { return nil }
        let n = db.tables().count
        return PreviewPage.page(title: url.lastPathComponent, kind: "SQLite · \(n) table\(n == 1 ? "" : "s")", body: body, theme: theme, css: css)
    }
}
