//
//  MarkdownHTMLTests.swift
//  MarkdownHTMLTests
//
//  Tests for `MarkdownHTML.render`: headings, emphasis, lists, code, links and tables produce
//  the expected HTML.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import MarkdownHTML

/// Tests for `MarkdownHTML.render`: headings, emphasis, lists, code, links and tables produce
/// the expected HTML.
final class MarkdownHTMLTests: XCTestCase {

    func testHeading() {
        let html = MarkdownHTML.render("# Hello")
        XCTAssertEqual(html, "<h1>Hello</h1>\n")
    }

    func testHeadingLevels() {
        XCTAssertTrue(MarkdownHTML.render("### Deep").contains("<h3>Deep</h3>"))
    }

    func testBold() {
        let html = MarkdownHTML.render("Some **bold** text.")
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<p>"))
    }

    func testEmphasis() {
        XCTAssertTrue(MarkdownHTML.render("An *italic* word.").contains("<em>italic</em>"))
    }

    func testUnorderedList() {
        // swift-markdown wraps each list item's content in a paragraph.
        let html = MarkdownHTML.render("- one\n- two")
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li><p>one</p>"))
        XCTAssertTrue(html.contains("<li><p>two</p>"))
    }

    func testOrderedList() {
        let html = MarkdownHTML.render("1. first\n2. second")
        XCTAssertTrue(html.contains("<ol>"))
        XCTAssertTrue(html.contains("<li><p>first</p>"))
    }

    func testOrderedListKeepsStartIndex() {
        let html = MarkdownHTML.render("3. three\n4. four")
        XCTAssertTrue(html.contains("<ol start=\"3\">"))
    }

    func testOrderedListStartingAtOneOmitsStartAttribute() {
        XCTAssertFalse(MarkdownHTML.render("1. first").contains("start="))
    }

    func testInlineCode() {
        XCTAssertTrue(MarkdownHTML.render("Use `let x = 1` here.").contains("<code>let x = 1</code>"))
    }

    func testFencedCodeBlock() {
        let html = MarkdownHTML.render("```swift\nlet x = 1\n```")
        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">"))
        XCTAssertTrue(html.contains("let x = 1"))
        XCTAssertTrue(html.contains("</code></pre>"))
    }

    func testLink() {
        let html = MarkdownHTML.render("[Apple](https://apple.com)")
        XCTAssertTrue(html.contains("<a href=\"https://apple.com\">Apple</a>"))
    }

    func testImage() {
        let html = MarkdownHTML.render("![alt text](img.png)")
        XCTAssertTrue(html.contains("<img src=\"img.png\" alt=\"alt text\">"))
    }

    func testStrikethrough() {
        XCTAssertTrue(MarkdownHTML.render("~~gone~~").contains("<del>gone</del>"))
    }

    func testBlockQuote() {
        XCTAssertTrue(MarkdownHTML.render("> quoted").contains("<blockquote>"))
    }

    func testThematicBreak() {
        XCTAssertTrue(MarkdownHTML.render("---").contains("<hr>"))
    }

    func testTable() {
        let md = """
            | A | B |
            | - | - |
            | 1 | 2 |
            """
        let html = MarkdownHTML.render(md)
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>A</th>"))
        XCTAssertTrue(html.contains("<td>1</td>"))
    }

    func testTaskList() {
        let html = MarkdownHTML.render("- [x] done\n- [ ] todo")
        XCTAssertTrue(html.contains("<li class=\"task\"><input type=\"checkbox\" disabled checked>"))
        XCTAssertTrue(html.contains("<li class=\"task\"><input type=\"checkbox\" disabled>"))
    }

    func testHTMLEscaping() {
        let html = MarkdownHTML.render("a < b & c > d")
        XCTAssertTrue(html.contains("&lt;"))
        XCTAssertTrue(html.contains("&amp;"))
        XCTAssertTrue(html.contains("&gt;"))
    }

    func testAttributeEscaping() {
        let html = MarkdownHTML.render("[link](\"weird\")")
        XCTAssertTrue(html.contains("&quot;"))
    }

    func testEscapingPreservesEntitiesAndNonASCII() {
        // Pre-escaped-looking text is double-escaped, and multi-byte characters pass through
        // untouched.
        let html = MarkdownHTML.render("`&lt; café < 日本 & \"q\"`")
        XCTAssertTrue(html.contains("<code>&amp;lt; café &lt; 日本 &amp; \"q\"</code>"))
    }

    func testRawInlineHTMLPassesThrough() {
        XCTAssertTrue(MarkdownHTML.render("text <span>raw</span> more").contains("<span>raw</span>"))
    }

    // MARK: - Security regressions

    func testFenceInfoStringCannotInjectAttributes() {
        // A double quote in the fence info string must not close the class
        // attribute and inject an event handler.
        let html = MarkdownHTML.render("```swift\" onmouseover=\"alert(1)\ncode\n```")
        XCTAssertFalse(html.contains("onmouseover=\"alert(1)\""))
        XCTAssertTrue(html.contains("class=\"language-swift&quot; onmouseover=&quot;alert(1)\""))
    }

    func testJavascriptLinkNeutralized() {
        let html = MarkdownHTML.render("[click](javascript:alert(document.cookie))")
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertTrue(html.contains("<a href=\"#\">click</a>"))
    }

    func testVbscriptLinkNeutralized() {
        let html = MarkdownHTML.render("[click](vbscript:MsgBox(1))")
        XCTAssertFalse(html.contains("vbscript:"))
        XCTAssertTrue(html.contains("href=\"#\""))
    }

    func testJavascriptSchemeCaseAndWhitespaceObfuscationNeutralized() {
        // Browsers ignore case and embedded tab/newline in the scheme.
        let html = MarkdownHTML.render("[click](<JaVa\tScRiPt:alert(1)>)")
        XCTAssertTrue(html.contains("href=\"#\""))
    }

    func testDataURILinkNeutralized() {
        let html = MarkdownHTML.render("[click](data:text/html,<script>alert(1)</script>)")
        XCTAssertFalse(html.contains("data:text/html"))
        XCTAssertTrue(html.contains("href=\"#\""))
    }

    func testJavascriptImageNeutralized() {
        let html = MarkdownHTML.render("![x](javascript:alert(1))")
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertTrue(html.contains("src=\"#\""))
    }

    func testImageDataURIAllowed() {
        let html = MarkdownHTML.render("![x](data:image/png;base64,iVBORw0KGgo=)")
        XCTAssertTrue(html.contains("src=\"data:image/png;base64,iVBORw0KGgo=\""))
    }

    func testNonImageDataURIImageNeutralized() {
        let html = MarkdownHTML.render("![x](data:text/html,<script>alert(1)</script>)")
        XCTAssertFalse(html.contains("data:text/html"))
        XCTAssertTrue(html.contains("src=\"#\""))
    }

    func testSafeLinksAndImagesUnaffected() {
        XCTAssertTrue(MarkdownHTML.render("[a](https://apple.com)").contains("href=\"https://apple.com\""))
        XCTAssertTrue(MarkdownHTML.render("[m](mailto:me@example.com)").contains("href=\"mailto:me@example.com\""))
        XCTAssertTrue(MarkdownHTML.render("[r](docs/page.md)").contains("href=\"docs/page.md\""))
        XCTAssertTrue(MarkdownHTML.render("![i](img.png)").contains("src=\"img.png\""))
    }

    func testADiagramFenceIsAPreOfItsSourceForTheHostsRenderer() {
        let md = "```mermaid\ngraph TD; A-->B\n```\n\n```swift\nlet x = 1\n```\n"
        let html = MarkdownHTML.render(md)
        XCTAssertTrue(
            html.contains("<pre class=\"mermaid\">graph TD; A--&gt;B\n</pre>"),
            "the source, escaped, in a pre the renderer replaces: \(html)")
        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">let x = 1\n</code></pre>"), "other fences are code as ever")
        XCTAssertTrue(
            MarkdownHTML.render(md, diagramFences: []).contains("<pre><code class=\"language-mermaid\">"),
            "with no diagram fences it is code")
        XCTAssertTrue(
            MarkdownHTML.render("```Mermaid \nA\n```").contains("<pre class=\"mermaid\">A\n</pre>"),
            "the tag reads case-insensitively, trimmed")
    }
}
