//
//  MarkdownHTML.swift
//  MarkdownHTML
//
//  Renders a CommonMark + GitHub-Flavored-Markdown document to HTML via Apple's
//  swift-markdown (cmark-gfm). Tables, task lists, strikethrough, nested lists,
//  images, code blocks, and raw HTML are all supported.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import Markdown

/// Renders Markdown to HTML.
///
/// A full CommonMark + GitHub-Flavored-Markdown document (parsed by Apple's
/// swift-markdown / cmark-gfm) is walked and emitted as HTML — tables, task
/// lists, strikethrough, nested lists, images, code blocks, raw HTML, the lot.
///
/// ```swift
/// import MarkdownHTML
///
/// let html = MarkdownHTML.render("# Hello\n\nSome **bold** text.")
/// // "<h1>Hello</h1>\n<p>Some <strong>bold</strong> text.</p>\n"
/// ```
public enum MarkdownHTML {

    /// Parses `markdown` and returns the rendered HTML.
    ///
    /// The input is treated as a complete Markdown document. Text and code are
    /// HTML-escaped; raw HTML embedded in the Markdown is passed through verbatim.
    ///
    /// - Parameters:
    ///   - markdown: The Markdown source to render.
    ///   - highlightCode: Optional syntax highlighter for fenced blocks. Given the block's
    ///     source and its fence tag (`swift`, `php`, …), it returns HTML for the inside of the
    ///     `<code>` element — already escaped — or nil to leave the block plain.
    ///
    ///     A closure rather than a dependency: highlighting means tree-sitter and a few dozen
    ///     grammars, and a Markdown-to-HTML library has no business pulling that in. The host
    ///     app owns both and wires them together, so this package stays what it says it is.
    ///   - math: Whether `$…$` and `$$…$$` are math (GitHub's and pandoc's reading; see
    ///     `MathSpans`). The TeX comes out untouched in `<span class="math math-inline">` /
    ///     `<span class="math math-display">` for the host's renderer; without one it shows as
    ///     written. Off, every dollar is prose.
    ///   - diagramFences: Fence tags whose blocks are diagrams, not code: each renders as
    ///     `<pre class="TAG">` holding the escaped source (GitHub's shape for ```` ```mermaid ````),
    ///     for the host's renderer to replace; without one the source shows as written. Empty,
    ///     every fence is code.
    /// - Returns: The rendered HTML fragment.
    public static func render(_ markdown: String,
                              highlightCode: ((String, String) -> String?)? = nil,
                              math: Bool = true,
                              diagramFences: Set<String> = ["mermaid"]) -> String {
        let (frontmatter, body) = splitFrontmatter(markdown)
        let extracted = math ? MathSpans.extract(body) : MathSpans.Extraction(markdown: body, spans: [])
        let document = Markdown.Document(parsing: normalizeBulletGlyphs(extracted.markdown))
        var renderer = HTMLRenderer(highlightCode: highlightCode, diagramFences: diagramFences)
        return frontmatterHTML(frontmatter) + MathSpans.restore(renderer.visit(document), spans: extracted.spans)
    }

    /// Bullet GLYPHS that people type where a Markdown list marker belongs.
    ///
    /// `•` is not list syntax — CommonMark knows only `-`, `*` and `+` — so a run of such lines
    /// is one paragraph, and lines within a paragraph join with spaces. Forty bulleted items
    /// become a single wall of text with `•` separators, which is strictly WORSE than reading
    /// the raw file. Common in exported or scraped documents nobody hand-authored.
    private static let bulletGlyphs: Set<Character> = ["•", "·", "▪", "‣", "●", "◦"]

    /// Rewrites bullet-glyph lines as real list items so they render as a list.
    ///
    /// Deliberately narrow. It fires only when a line's first non-space character is one of
    /// ``bulletGlyphs`` AND a space follows, and it never touches anything inside a fenced code
    /// block — where a bullet is content, not intent. Indentation is preserved so nested items
    /// stay nested.
    ///
    /// The blunter alternative — rendering every soft line break as `<br>` — would fix this case
    /// and break every hard-wrapped document, since plenty of Markdown wraps prose at 80 columns
    /// and would come out ragged. Fixing the marker is the smaller claim: it changes only lines
    /// that were already trying to be a list.
    static func normalizeBulletGlyphs(_ markdown: String) -> String {
        guard markdown.contains(where: { bulletGlyphs.contains($0) }) else { return markdown }
        var inFence = false
        let lines = markdown.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                return line
            }
            guard !inFence,
                  let first = trimmed.first, bulletGlyphs.contains(first),
                  trimmed.dropFirst().hasPrefix(" ")
            else { return line }
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            return indent + "- " + trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        return lines.joined(separator: "\n")
    }

    /// Splits leading YAML frontmatter from the body.
    ///
    /// CommonMark has no concept of frontmatter, and left in place it does not merely render as
    /// stray text — it renders WRONG. The opening `---` is a thematic break, the `key: value`
    /// lines become a paragraph, and the closing `---` is then read as a setext heading
    /// underline for that paragraph, so an entire metadata block turns into one enormous `<h2>`.
    ///
    /// Recognised only when the document's FIRST line is exactly `---` and a matching closing
    /// fence exists, so an ordinary document that opens with a thematic break is untouched.
    ///
    /// - Returns: The frontmatter's key/value pairs in document order, and the body without it.
    static func splitFrontmatter(_ markdown: String) -> (pairs: [(key: String, value: String)], body: String) {
        // `.whitespacesAndNewlines` throughout: a file authored on Windows ends every line in
        // CRLF, and CR is not in `.whitespaces`, so `---\r` was never a fence (18 Sep 2026).
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return ([], markdown) }
        guard let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---" })
        else { return ([], markdown) }

        var pairs: [(String, String)] = []
        var pendingKey: String?          // a `key: |` or `key: >` block scalar
        var blockLines: [String] = []

        func flushBlock() {
            if let k = pendingKey {
                pairs.append((k, blockLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)))
                pendingKey = nil
                blockLines = []
            }
        }

        for raw in lines[1..<close] {
            // Indented continuation of a block scalar, or a list item under a key.
            if pendingKey != nil, raw.hasPrefix(" ") || raw.hasPrefix("\t") {
                blockLines.append(raw.trimmingCharacters(in: .whitespacesAndNewlines))
                continue
            }
            flushBlock()
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            // `|` and `>` introduce a block scalar whose text is on the following indented lines.
            if value == "|" || value == ">" || value == "|-" || value == ">-" {
                pendingKey = key
                continue
            }
            // Unwrap the quoting YAML allows around a scalar.
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            pairs.append((key, value))
        }
        flushBlock()

        let body = lines[(close + 1)...].joined(separator: "\n")
        return (pairs, body)
    }

    /// Renders frontmatter as a small definition table above the body.
    ///
    /// Shown rather than stripped: slug, title, url and counts are facts about the document, and
    /// hiding them would mean the preview silently omits half of what the file says. Values that
    /// look like links are linked, so a `url:` field is usable rather than just readable.
    /// Shared HTML escaping — the frontmatter table and the body renderer must agree, and two
    /// implementations of "escape this" is how one of them ends up not escaping quotes.
    static func escaped(_ s: String, forAttribute: Bool) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"" where forAttribute: out += "&quot;"
            default:  out.append(ch)
            }
        }
        return out
    }

    static func frontmatterHTML(_ pairs: [(key: String, value: String)]) -> String {
        guard !pairs.isEmpty else { return "" }
        var rows = ""
        for (key, value) in pairs {
            let shown: String
            if value.hasPrefix("http://") || value.hasPrefix("https://") {
                shown = "<a href=\"\(escaped(value, forAttribute: true))\">\(escaped(value, forAttribute: false))</a>"
            } else {
                shown = escaped(value, forAttribute: false)
            }
            rows += "<tr><th>\(escaped(key, forAttribute: false))</th><td>\(shown)</td></tr>\n"
        }
        return "<table class=\"frontmatter\">\n\(rows)</table>\n"
    }
}

/// Walks a parsed Markdown tree and emits HTML for each node.
///
/// Kept private to the module: it is the rendering machinery behind
/// ``MarkdownHTML/render(_:)`` and not part of the public surface.
private struct HTMLRenderer: MarkupVisitor {

    /// Optional per-block syntax highlighter — see ``MarkdownHTML/render(_:highlightCode:)``.
    let highlightCode: ((String, String) -> String?)?
    /// Fence tags rendered as `<pre class="TAG">` diagrams rather than code.
    let diagramFences: Set<String>

    typealias Result = String

    /// Renders a node's children in order and concatenates the results.
    mutating func defaultVisit(_ markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    mutating func visitText(_ text: Text) -> String { esc(text.string) }
    mutating func visitParagraph(_ p: Paragraph) -> String { "<p>\(defaultVisit(p))</p>\n" }
    mutating func visitHeading(_ h: Heading) -> String { "<h\(h.level)>\(defaultVisit(h))</h\(h.level)>\n" }
    mutating func visitEmphasis(_ e: Emphasis) -> String { "<em>\(defaultVisit(e))</em>" }
    mutating func visitStrong(_ s: Strong) -> String { "<strong>\(defaultVisit(s))</strong>" }
    mutating func visitStrikethrough(_ s: Strikethrough) -> String { "<del>\(defaultVisit(s))</del>" }
    mutating func visitInlineCode(_ c: InlineCode) -> String { "<code>\(esc(c.code))</code>" }
    mutating func visitBlockQuote(_ b: BlockQuote) -> String { "<blockquote>\(defaultVisit(b))</blockquote>\n" }
    mutating func visitUnorderedList(_ l: UnorderedList) -> String { "<ul>\n\(defaultVisit(l))</ul>\n" }
    mutating func visitOrderedList(_ l: OrderedList) -> String {
        let start = l.startIndex == 1 ? "" : " start=\"\(l.startIndex)\""
        return "<ol\(start)>\n\(defaultVisit(l))</ol>\n"
    }
    mutating func visitThematicBreak(_ t: ThematicBreak) -> String { "<hr>\n" }
    mutating func visitLineBreak(_ l: LineBreak) -> String { "<br>\n" }
    mutating func visitSoftBreak(_ s: SoftBreak) -> String { " " }
    mutating func visitInlineHTML(_ h: InlineHTML) -> String { h.rawHTML }
    mutating func visitHTMLBlock(_ h: HTMLBlock) -> String { h.rawHTML }

    mutating func visitCodeBlock(_ c: CodeBlock) -> String {
        // A diagram fence is its source in a `<pre class="TAG">`, for the host's renderer.
        if let tag = c.language?.trimmingCharacters(in: .whitespaces).lowercased(), diagramFences.contains(tag) {
            return "<pre class=\"\(escAttr(tag))\">\(esc(c.code))</pre>\n"
        }
        let cls = c.language.map { " class=\"language-\(escAttr($0))\"" } ?? ""
        // Highlighted when a highlighter is supplied AND recognises the tag; otherwise the
        // escaped source exactly as before. An unknown tag, or no highlighter at all, renders
        // what it always did rather than something half-coloured.
        if let tag = c.language, let highlighted = highlightCode?(c.code, tag) {
            return "<pre><code\(cls)>\(highlighted)</code></pre>\n"
        }
        return "<pre><code\(cls)>\(esc(c.code))</code></pre>\n"
    }

    mutating func visitListItem(_ item: ListItem) -> String {
        let inner = defaultVisit(item)
        if let box = item.checkbox {
            let checked = box == .checked ? " checked" : ""
            return "<li class=\"task\"><input type=\"checkbox\" disabled\(checked)>\(inner)</li>\n"
        }
        return "<li>\(inner)</li>\n"
    }

    mutating func visitLink(_ l: Link) -> String {
        "<a href=\"\(escAttr(safeURL(l.destination ?? "")))\">\(defaultVisit(l))</a>"
    }

    mutating func visitImage(_ img: Image) -> String {
        "<img src=\"\(escAttr(safeURL(img.source ?? "", allowImageData: true)))\" alt=\"\(escAttr(img.plainText))\">"
    }

    // Tables (GFM)
    mutating func visitTable(_ table: Table) -> String {
        "<table>\n\(visit(table.head))\(visit(table.body))</table>\n"
    }
    mutating func visitTableHead(_ head: Table.Head) -> String {
        "<thead><tr>" + head.children.map { "<th>\(visit($0))</th>" }.joined() + "</tr></thead>\n"
    }
    mutating func visitTableBody(_ body: Table.Body) -> String {
        "<tbody>\n" + body.children.map { visit($0) }.joined() + "</tbody>\n"
    }
    mutating func visitTableRow(_ row: Table.Row) -> String {
        "<tr>" + row.children.map { "<td>\(visit($0))</td>" }.joined() + "</tr>\n"
    }
    mutating func visitTableCell(_ cell: Table.Cell) -> String { defaultVisit(cell) }

    /// Neutralizes dangerous URL schemes in a link/image destination.
    ///
    /// `javascript:`, `vbscript:`, and (unless `allowImageData` is set and the
    /// URI is an image) `data:` destinations are replaced with `"#"` so an
    /// untrusted document can't smuggle a script-executing URL into an
    /// `href`/`src`. The scheme check strips whitespace/control characters
    /// first, matching how browsers tolerate them inside URLs.
    private func safeURL(_ s: String, allowImageData: Bool = false) -> String {
        let scheme = String(s.lowercased().unicodeScalars.filter { $0.value > 0x20 })
        if scheme.hasPrefix("javascript:") || scheme.hasPrefix("vbscript:") { return "#" }
        if scheme.hasPrefix("data:") {
            return allowImageData && scheme.hasPrefix("data:image/") ? s : "#"
        }
        return s
    }

    /// Escapes `&`, `<`, and `>` for use in HTML text content.
    ///
    /// Single UTF-8 pass with a no-specials early return — this runs on every
    /// text/code node of the live preview's per-pause re-render, and the chained
    /// `replacingOccurrences` form it replaces bridged the string through
    /// NSString once per pattern.
    private func esc(_ s: String) -> String { escaped(s, forAttribute: false) }

    /// Escapes text-content characters plus `"` for use inside a quoted HTML attribute.
    private func escAttr(_ s: String) -> String { escaped(s, forAttribute: true) }

    private func escaped(_ s: String, forAttribute: Bool) -> String {
        MarkdownHTML.escaped(s, forAttribute: forAttribute)
    }

}
