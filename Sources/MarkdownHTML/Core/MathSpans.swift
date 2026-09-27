//
//  MathSpans.swift
//  MarkdownHTML
//
//  `$…$` and `$$…$$` lifted out of the Markdown before parsing and put back after, so the
//  TeX inside reaches the page untouched for a math renderer to typeset.
//
//  Created by David Sherlock on 9/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Math spans, the way GitHub and pandoc read them: `$$…$$` is display math (it may span
/// lines), `$…$` is inline math on one line whose opening `$` is followed by a non-space and
/// whose closing `$` is preceded by a non-space and not followed by a digit — so "$5 and $10"
/// is prose. Nothing inside a fenced code block or inline code is math, and `\$` is a dollar.
///
/// The TeX is replaced by a private-use placeholder before the Markdown parse (so `a_1` in it
/// is not emphasis and `\\` is not an escape) and restored after as
/// `<span class="math math-inline">` or `<span class="math math-display">` holding the
/// HTML-escaped TeX. The renderer is the host's: KaTeX, MathJax, or none, in which case the
/// TeX shows as written.
enum MathSpans {

    /// The Markdown with every math span replaced by a placeholder, and the spans' HTML in order.
    struct Extraction: Equatable {
        let markdown: String
        let spans: [String]
    }

    /// Wraps each placeholder: `\u{E000}` + index + `\u{E000}`, characters no document uses.
    private static let mark: Character = "\u{E000}"

    static func extract(_ markdown: String) -> Extraction {
        guard markdown.contains("$") else { return Extraction(markdown: markdown, spans: []) }
        var spans: [String] = []
        var out = ""
        var inFence: String? = nil
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let fence = inFence {
                out += line + (i < lines.count - 1 ? "\n" : "")
                if trimmed.hasPrefix(fence) { inFence = nil }
                i += 1
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence = String(trimmed.prefix(3))
                out += line + (i < lines.count - 1 ? "\n" : "")
                i += 1
                continue
            }
            // A `$$` block may run over several lines: gather them into one text to scan.
            var text = line
            var consumed = 1
            if let open = text.range(of: "$$"), text[open.upperBound...].range(of: "$$") == nil {
                var j = i + 1
                while j < lines.count {
                    text += "\n" + lines[j]
                    consumed += 1
                    if lines[j].contains("$$") { break }
                    j += 1
                }
                if text[open.upperBound...].range(of: "$$") == nil { text = line; consumed = 1 }   // never closed
            }
            out += scanLine(text, spans: &spans)
            i += consumed
            if i <= lines.count - 1 { out += "\n" }
        }
        return Extraction(markdown: out, spans: spans)
    }

    /// One line (or a gathered `$$` block) with its math replaced by placeholders.
    private static func scanLine(_ text: String, spans: inout [String]) -> String {
        let chars = Array(text)
        var out = ""
        var i = 0
        var inCode = false
        while i < chars.count {
            let c = chars[i]
            if c == "`" { inCode.toggle(); out.append(c); i += 1; continue }
            if inCode { out.append(c); i += 1; continue }
            if c == "\\", i + 1 < chars.count { out.append(c); out.append(chars[i + 1]); i += 2; continue }
            if c == "$" {
                if i + 1 < chars.count, chars[i + 1] == "$" {
                    if let close = closingDouble(in: chars, from: i + 2) {
                        let tex = String(chars[(i + 2)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !tex.isEmpty {
                            out += placeholder(spans.count)
                            spans.append("<span class=\"math math-display\">\(MarkdownHTML.escaped(tex, forAttribute: false))</span>")
                            i = close + 2
                            continue
                        }
                    }
                } else if let close = closingSingle(in: chars, from: i + 1) {
                    let tex = String(chars[(i + 1)..<close])
                    out += placeholder(spans.count)
                    spans.append("<span class=\"math math-inline\">\(MarkdownHTML.escaped(tex, forAttribute: false))</span>")
                    i = close + 1
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return out
    }

    private static func placeholder(_ n: Int) -> String { "\(mark)\(n)\(mark)" }

    /// The index of the closing `$$` at or after `from`, or nil.
    private static func closingDouble(in chars: [Character], from: Int) -> Int? {
        var i = from
        while i + 1 < chars.count {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == "$", chars[i + 1] == "$" { return i }
            i += 1
        }
        return nil
    }

    /// The index of the closing `$` of an inline span opened just before `from`, or nil:
    /// the span is non-empty, on one line, opens before a non-space, closes after a non-space
    /// and not before a digit.
    private static func closingSingle(in chars: [Character], from: Int) -> Int? {
        guard from < chars.count, !chars[from].isWhitespace, chars[from] != "$" else { return nil }
        var i = from
        while i < chars.count {
            let c = chars[i]
            if c == "\n" { return nil }
            if c == "\\" { i += 2; continue }
            if c == "$" {
                let before = chars[i - 1]
                let after: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                if !before.isWhitespace, after?.isNumber != true { return i }
                return nil
            }
            i += 1
        }
        return nil
    }

    /// The rendered HTML with each placeholder replaced by its span.
    static func restore(_ html: String, spans: [String]) -> String {
        guard !spans.isEmpty else { return html }
        var out = html
        for (n, span) in spans.enumerated() { out = out.replacingOccurrences(of: placeholder(n), with: span) }
        return out
    }
}
