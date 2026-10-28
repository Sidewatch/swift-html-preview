//
//  PendingFencesTests.swift
//  MarkdownHTMLTests
//
//  A page built with its fences coloured later is the page `render` makes; fences come in page order, a declined one
//  is its escaped source, and a placeholder never meets the document's own text.
//
//  Created by David Sherlock on 10/28/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest

@testable import MarkdownHTML

final class PendingFencesTests: XCTestCase {
    /// A highlighter for two tags: anything it colours is marked so a misplaced block shows.
    private func highlight(_ code: String, _ tag: String) -> String? {
        ["swift", "py"].contains(tag) ? "<b data-tag=\"\(tag)\">\(code.count)</b>" : nil
    }

    private let document = """
        ---
        title: Fences
        ---
        # Fences

        Some $x_1$ math and a `code span`.

        ```swift
        let a = 1 < 2
        ```

        ```text
        plain <text>
        ```

        | a | b |
        |---|---|
        | 1 | 2 |

        ```mermaid
        graph TD; A-->B
        ```

        ```py
        print("b")
        ```

        ```
        untagged
        ```

        $$
        \\int x\\,dx
        $$
        """

    /// The page put together from its pending fences is byte for byte the page `render` makes with the same highlighter.
    func testFilledIsThePageRenderMakes() {
        let pending = MarkdownHTML.renderPendingFences(document, highlights: { self.highlight("", $0) != nil })
        let filled = pending.filled(with: pending.fences.map { highlight($0.code, $0.tag) })
        XCTAssertEqual(filled, MarkdownHTML.render(document, highlightCode: highlight))
        XCTAssertTrue(filled.contains("<b data-tag=\"swift\">"), filled)
    }

    /// Only the fences the highlighter takes wait, in the order the page holds them, with their source and tag.
    func testFencesComeInPageOrder() {
        let pending = MarkdownHTML.renderPendingFences(document, highlights: { self.highlight("", $0) != nil })
        XCTAssertEqual(
            pending.fences, [PendingFence(code: "let a = 1 < 2\n", tag: "swift"), PendingFence(code: "print(\"b\")\n", tag: "py")])
        XCTAssertFalse(pending.html.contains("let a = 1"), "a waiting block's source is not on the page yet")
    }

    /// A fence the highlighter gives nothing for is its escaped source, as `render` writes a declined block.
    func testADeclinedFenceIsItsEscapedSource() {
        let pending = MarkdownHTML.renderPendingFences("```swift\na < b && c\n```\n", highlights: { _ in true })
        XCTAssertEqual(pending.filled(with: [nil]), "<pre><code class=\"language-swift\">a &lt; b &amp;&amp; c\n</code></pre>\n")
        XCTAssertEqual(pending.filled(with: []), pending.filled(with: [nil]), "a short answer leaves the rest plain")
    }

    /// The placeholder's character is one the document does not use: text holding the first candidate, even shaped
    /// like a placeholder, survives as written, and the fence is still filled once.
    func testAPlaceholderNeverMeetsTheDocumentsOwnText() {
        let own = "\u{E001}0\u{E001} and \u{E002}"
        let pending = MarkdownHTML.renderPendingFences("\(own)\n\n```swift\nx\n```\n", highlights: { _ in true })
        XCTAssertEqual(pending.mark, "\u{E003}")
        let filled = pending.filled(with: ["<i>x</i>"])
        XCTAssertTrue(filled.hasPrefix("<p>\(own)</p>"), filled)
        XCTAssertEqual(filled.components(separatedBy: "<i>x</i>").count, 2, filled)
    }

    /// A page with nothing to colour is the rendered page as it stands.
    func testNoFencesIsTheRenderedPage() {
        let pending = MarkdownHTML.renderPendingFences("# Title\n\nText.\n", highlights: { _ in true })
        XCTAssertEqual(pending.fences, [])
        XCTAssertEqual(pending.filled(with: []), MarkdownHTML.render("# Title\n\nText.\n"))
    }
}
