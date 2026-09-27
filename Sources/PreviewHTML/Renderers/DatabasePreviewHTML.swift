//
//  DatabasePreviewHTML.swift
//  PreviewHTML
//
//  A SQLite database as its tables, one tab each: columns, row count, the first rows, filtered live.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import SQLiteReader
import FoundationExtensions

/// A SQLite database as its tables, one tab per table: the bar lists the tables with their row
/// counts, the chosen one shows its columns (declared type, key, not null), its first rows, and
/// the filter field narrows the rows. The tabs are CSS radio inputs — no script switches them.
/// Read-only through `SQLiteDB`; a file is a database by its 16-byte header, whatever its name.
public enum DatabasePreviewHTML {
    /// The most rows each table's panel shows.
    public static let rowsPerTable = 200
    /// The most tables that get a tab; the rest are counted in the bar.
    public static let tableCap = 40
    /// The 16-byte header every SQLite file begins with, `SQLite format 3\0`.
    static let magic = Data("SQLite format 3\u{0}".utf8)

    /// Whether `data` (its first bytes) is a SQLite file.
    public static func isSQLite(_ data: Data) -> Bool { data.count >= magic.count && data.prefix(magic.count) == magic }

    /// The body: the radios, the bar of tabs, one panel per table.
    public static func body(databaseAt url: URL) -> String? {
        guard let db = SQLiteDB(url: url) else { return nil }
        let tables = Array(db.tables().prefix(tableCap))
        if tables.isEmpty {
            return
                "<div class=\"note\">\(String(localized: "No tables.", bundle: .module, comment: "Quick Look database preview: the database has no tables."))</div>"
        }
        var radios = "", labels = "", panels = ""
        for (i, table) in tables.enumerated() {
            let count = db.rowCount(table)
            radios += "<input class=\"tab\" type=\"radio\" name=\"tab\" id=\"tab\(i)\"\(i == 0 ? " checked" : "")>"
            labels += "<label for=\"tab\(i)\">\(PreviewPage.escape(table))<span class=\"n\">\(PreviewPage.grouped(count))</span></label>"
            panels += panel(db: db, table: table, index: i, count: count)
        }
        let more =
            db.tables().count > tableCap
            ? "<span class=\"count\">\(String(localized: "\(db.tables().count - tableCap) more tables", bundle: .module, comment: "Quick Look database preview bar: tables beyond the tab limit, not shown."))</span>"
            : ""
        return radios + "\n<div class=\"bar\"><div class=\"tabs\">" + labels + "</div>" + more
            + PreviewPage.filterField(
                placeholder: String(
                    localized: "Filter rows", bundle: .module, comment: "Quick Look table preview: placeholder in the filter field."))
            + "</div>\n" + panels
    }

    /// One table's panel: its columns, how many rows it has and shows, and the rows.
    static func panel(db: SQLiteDB, table: String, index: Int, count: Int) -> String {
        let columns = db.schema(table)
        var out = "<section class=\"panel\" id=\"p\(index)\">\n<div class=\"meta\">"
        out += columns.map { c in
            "<span class=\"col\">\(c.pk ? "<b>⚿</b> " : "")\(PreviewPage.escape(c.name)) <i>\(PreviewPage.escape(c.type.isEmpty ? "any" : c.type))\(c.notNull ? " not null" : "")</i></span>"
        }.joined(separator: " ")
        out +=
            "</div>\n<div class=\"meta\">"
            + String(
                localized: "\(count) rows", bundle: .module,
                comment: "Quick Look table preview bar: how many data rows the file or table has.")
        if count > rowsPerTable {
            out +=
                " · "
                + String(
                    localized: "first \(rowsPerTable)", bundle: .module,
                    comment: "Quick Look table preview bar: only the first this-many rows are shown.")
        }
        out += "<span class=\"shown\" id=\"shown-d\(index)\"></span></div>\n"
        let result = db.run("SELECT * FROM \(SQLiteDB.quoteIdentifier(table)) LIMIT \(rowsPerTable)", limit: rowsPerTable)
        if !result.rows.isEmpty {
            out +=
                "<table class=\"data\" id=\"d\(index)\"><thead><tr>" + result.columns.map { "<th>\(PreviewPage.escape($0))</th>" }.joined()
                + "</tr></thead><tbody>\n"
            for row in result.rows { out += "<tr class=\"row\">" + row.map { "<td>\(PreviewPage.escape($0))</td>" }.joined() + "</tr>\n" }
            out += "</tbody></table>\n"
        }
        return out + "</section>\n"
    }

    /// The tab rules for up to `tableCap` tables: the checked radio shows its label as chosen
    /// and its panel at all.
    static var css: String {
        var rules =
            TablePreviewHTML.css + """
                .col { margin-right: 10px; white-space: nowrap; }
                .col i { color: var(--gutter); font-style: normal; }
                .col b { color: var(--accent); font-weight: 400; }

                """
        for i in 0..<tableCap {
            rules +=
                "#tab\(i):checked ~ .bar label[for=tab\(i)] { background: var(--accent); color: #FFFFFF; } #tab\(i):checked ~ .bar label[for=tab\(i)] .n { opacity: 0.85; } #tab\(i):checked ~ #p\(i) { display: block; }\n"
        }
        return rules
    }

    /// The whole page for the database at `url`, or nil when it cannot be opened.
    public static func page(databaseAt url: URL, theme: ThemeSnapshot?) -> String? {
        guard let body = body(databaseAt: url) else { return nil }
        return PreviewPage.page(title: url.lastPathComponent, body: body, theme: theme, css: css, script: PreviewPage.filterScript)
    }
}
