//
//  MarkdownHTML+PendingFences.swift
//  MarkdownHTML
//
//  A page rendered with its code blocks coloured later, and put together once they are.
//
//  Created by David Sherlock on 10/28/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

extension MarkdownHTML {
    /// ``render(_:highlightCode:math:diagramFences:)`` with the colouring left for later: each fenced block whose tag
    /// `highlights` accepts stands as a placeholder in the page, and ``PendingFences/filled(with:)`` puts the coloured
    /// blocks in. For a host whose highlighter runs on one thread only: the page is built on any other, just the
    /// fences go to the highlighter, and the result is the page `render` makes with that highlighter.
    public static func renderPendingFences(
        _ markdown: String, highlights: (String) -> Bool, math: Bool = true, diagramFences: Set<String> = ["mermaid"]
    ) -> PendingFences {
        let mark = PendingFences.mark(absentFrom: markdown)
        var fences: [PendingFence] = []
        let html = withoutActuallyEscaping(highlights) { highlights in
            render(
                markdown,
                highlightCode: { code, tag in
                    guard highlights(tag) else { return nil }
                    fences.append(PendingFence(code: code, tag: tag))
                    return PendingFences.placeholder(fences.count - 1, mark: mark)
                }, math: math, diagramFences: diagramFences)
        }
        return PendingFences(html: html, fences: fences, mark: mark)
    }
}

extension PendingFences {
    /// The page with each fence's coloured HTML in its place: `highlighted[n]` for the nth of ``fences``. A nil, or a
    /// fence past the array's end, puts back the block's escaped source, as
    /// ``MarkdownHTML/render(_:highlightCode:math:diagramFences:)`` writes a block its highlighter declines. One pass
    /// over the page, however many fences it holds.
    public func filled(with highlighted: [String?]) -> String {
        guard !fences.isEmpty else { return html }
        let separator = Character(mark)
        let parts = html.split(separator: separator, omittingEmptySubsequences: false)
        var out = ""
        out.reserveCapacity(html.utf8.count + highlighted.reduce(0) { $0 + ($1?.utf8.count ?? 0) })
        var i = 0
        while i < parts.count {
            out += parts[i]
            // parts[i + 1] sits between two marks: a fence's number.
            if i + 2 < parts.count, let n = Int(parts[i + 1]), fences.indices.contains(n) {
                let coloured = highlighted.indices.contains(n) ? highlighted[n] : nil
                out += coloured ?? MarkdownHTML.escaped(fences[n].code, forAttribute: false)
                i += 2
            } else if i + 1 < parts.count {
                out.append(separator)
                i += 1
            } else {
                i += 1
            }
        }
        return out
    }

    /// The first private-use character from U+E001 up that `markdown` does not hold (U+E000 is the math spans'), so a
    /// placeholder is never the document's own text.
    static func mark(absentFrom markdown: String) -> Unicode.Scalar {
        let candidates: ClosedRange<UInt32> = 0xE001...0xF8FF
        var used = Set<UInt32>()
        for scalar in markdown.unicodeScalars where candidates.contains(scalar.value) { used.insert(scalar.value) }
        let free = candidates.first { !used.contains($0) } ?? candidates.lowerBound
        return Unicode.Scalar(free) ?? "\u{E001}"
    }

    /// The nth fence's placeholder: its number between two marks.
    static func placeholder(_ n: Int, mark: Unicode.Scalar) -> String { "\(Character(mark))\(n)\(Character(mark))" }
}
