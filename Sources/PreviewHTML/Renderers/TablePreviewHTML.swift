//
//  TablePreviewHTML.swift
//  PreviewHTML
//
//  CSV and TSV as a table with a header row.
//
//  Created by David Sherlock on 9/24/26.
//

import Foundation
import DataConverter

/// CSV (quote-aware, through `DataConverter.csvRecords`) and TSV as an HTML table: the first
/// record is the header, the rest the rows, capped so a million-line export is a glance.
public enum TablePreviewHTML {
    public static let rowCap = 500
    static let css = """
        table.data { border-collapse: collapse; font: 12px -apple-system, system-ui, sans-serif; margin: 8px 12px; }
        table.data th, table.data td { text-align: left; padding: 3px 10px; border-bottom: 1px solid var(--border); white-space: pre; }
        table.data th { color: var(--muted); font-weight: 600; position: sticky; top: 29px; background: var(--bg); }
        table.data td.num { text-align: right; color: var(--gutter); user-select: none; }
        """

    /// The records of `text`: CSV through the quote-aware tokenizer, TSV split on tabs per line.
    public static func records(_ text: String, tabSeparated: Bool) -> [[String]] {
        if tabSeparated {
            return text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
                .filter { !$0.isEmpty }.map { $0.components(separatedBy: "\t") }
        }
        return DataConverter.csvRecords(text)
    }

    /// The body: a header row from the first record, then up to `rowCap` rows, numbered.
    public static func body(records: [[String]]) -> String {
        guard let header = records.first else { return "<div class=\"note\">Empty.</div>" }
        var out = "<table class=\"data\"><thead><tr><th></th>" + header.map { "<th>\(PreviewPage.escape($0))</th>" }.joined() + "</tr></thead><tbody>\n"
        for (i, row) in records.dropFirst().prefix(rowCap).enumerated() {
            out += "<tr><td class=\"num\">\(i + 1)</td>" + row.map { "<td>\(PreviewPage.escape($0))</td>" }.joined() + "</tr>\n"
        }
        return out + "</tbody></table>"
    }

    /// The whole page for `text` named `title`.
    public static func page(title: String, text: String, tabSeparated: Bool, theme: ThemeSnapshot?) -> String {
        let recs = records(text, tabSeparated: tabSeparated)
        let rows = max(0, recs.count - 1)
        let note = rows > rowCap ? "Showing the first \(rowCap) of \(rows) rows." : nil
        return PreviewPage.page(title: title, kind: tabSeparated ? "TSV · \(rows) rows" : "CSV · \(rows) rows", body: body(records: recs), note: note, theme: theme, css: css)
    }
}
