//
//  TablePreviewHTML.swift
//  PreviewHTML
//
//  CSV and TSV as a table with a header row, filtered live.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import DataConverter
import FoundationExtensions

/// CSV (quote-aware, through `DataConverter.csvRecords`) and TSV as an HTML table: the first
/// record is the header, the rest the rows, capped so a million-line export is a glance, with
/// a filter field in the bar that narrows the rows as the user types.
public enum TablePreviewHTML {
    /// The most data rows the table shows; the bar says when there are more.
    public static let rowCap = 500
    /// The data-table rules, shared by the archive and database renderers.
    static let css = """
        table.data { border-collapse: collapse; font: 12px -apple-system, system-ui, sans-serif; margin: 8px 12px; width: calc(100% - 24px); }
        table.data th:last-child, table.data td:last-child { width: 100%; }
        table.data th, table.data td { text-align: left; padding: 3px 10px; border-bottom: 1px solid var(--border); white-space: pre; }
        table.data th { color: var(--muted); font-weight: 600; position: sticky; top: \(PreviewPage.barHeight)px; background: var(--bg); }
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

    /// One table (`id` names it for the filter's count): a header row from the first record,
    /// then up to `rowCap` rows, numbered.
    public static func table(id: String, records: [[String]]) -> String {
        guard let header = records.first else {
            return
                "<div class=\"note\">\(String(localized: "Empty.", bundle: .module, comment: "Quick Look CSV/TSV preview: the file has no rows."))</div>"
        }
        var out =
            "<table class=\"data\" id=\"\(id)\"><thead><tr><th></th>" + header.map { "<th>\(PreviewPage.escape($0))</th>" }.joined()
            + "</tr></thead><tbody>\n"
        for (i, row) in records.dropFirst().prefix(rowCap).enumerated() {
            out +=
                "<tr class=\"row\"><td class=\"num\">\(i + 1)</td>" + row.map { "<td>\(PreviewPage.escape($0))</td>" }.joined() + "</tr>\n"
        }
        return out + "</tbody></table>"
    }

    /// The body: the bar (kind, row count, the filter field) over the table.
    public static func body(records: [[String]], kind: String) -> String {
        let rows = max(0, records.count - 1)
        var parts = [
            kind,
            String(
                localized: "\(rows) rows", bundle: .module,
                comment: "Quick Look table preview bar: how many data rows the file or table has."),
        ]
        if rows > rowCap {
            parts.append(
                String(
                    localized: "first \(rowCap)", bundle: .module,
                    comment: "Quick Look table preview bar: only the first this-many rows are shown."))
        }
        let count = parts.joined(separator: " · ")
        return
            "<div class=\"bar\"><span class=\"count\">\(count)</span><span class=\"meta shown\" id=\"shown-t\"></span>\(PreviewPage.filterField(placeholder: String(localized: "Filter rows", bundle: .module, comment: "Quick Look table preview: placeholder in the filter field.")))</div>\n"
            + table(id: "t", records: records)
    }

    /// The whole page for `text` named `title`.
    public static func page(title: String, text: String, tabSeparated: Bool, theme: ThemeSnapshot?) -> String {
        let recs = records(text, tabSeparated: tabSeparated)
        return PreviewPage.page(
            title: title, body: body(records: recs, kind: tabSeparated ? "TSV" : "CSV"), theme: theme, css: css,
            script: PreviewPage.filterScript)
    }
}
