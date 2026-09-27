//
//  FrontmatterTests.swift
//  MarkdownHTMLTests
//
//  Covers YAML frontmatter handling.
//
//  Created by David Sherlock on 8/6/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import MarkdownHTML

/// Covers YAML frontmatter handling.
///
/// CommonMark has no frontmatter, and left alone it does not merely render as stray text — it
/// renders WRONG. `---` opens a thematic break, the `key: value` lines become a paragraph, and
/// the closing `---` is then read as a setext heading underline for that paragraph, so a whole
/// metadata block collapses into one enormous `<h2>`. The recognition has to be conservative,
/// though: a document that legitimately opens with a thematic break must be left alone.
final class FrontmatterTests: XCTestCase {

    // MARK: - Recognition

    func testSplitsSimpleFrontmatter() {
        let (pairs, body) = MarkdownHTML.splitFrontmatter("---\ntitle: Hello\nslug: hello\n---\nBody text.")
        XCTAssertEqual(pairs.map(\.key), ["title", "slug"])
        XCTAssertEqual(pairs.map(\.value), ["Hello", "hello"])
        XCTAssertEqual(body, "Body text.")
    }

    /// A CRLF file ends every line in CR, which `.whitespaces` does not contain; `---\r` must
    /// still count as a fence, or the metadata renders as the `<h2>` described above.
    func testCRLFFrontmatterIsRecognised() {
        let md = "---\r\ntitle: Hello\r\nslug: hello\r\n---\r\nBody text.\r\n"
        let (pairs, body) = MarkdownHTML.splitFrontmatter(md)
        XCTAssertEqual(pairs.map(\.key), ["title", "slug"])
        XCTAssertEqual(pairs.map(\.value), ["Hello", "hello"])
        XCTAssertFalse(body.contains("title"), "the metadata is out of the body")
        XCTAssertTrue(body.hasPrefix("Body text."))
        XCTAssertFalse(MarkdownHTML.render(md).contains("<h2"), "and it never becomes a heading")
    }

    /// The whole point of the conservatism: a horizontal rule is not frontmatter.
    func testLeavesAThematicBreakAlone() {
        let md = "---\n\nJust a document that opens with a rule."
        let (pairs, body) = MarkdownHTML.splitFrontmatter(md)
        XCTAssertTrue(pairs.isEmpty)
        XCTAssertEqual(body, md, "body must be untouched when there is no closing fence")
    }

    /// `---` further down is a thematic break, not the start of frontmatter.
    func testOnlyRecognisedAtTheVeryTop() {
        let md = "# Title\n\n---\nkey: value\n---\n"
        let (pairs, body) = MarkdownHTML.splitFrontmatter(md)
        XCTAssertTrue(pairs.isEmpty)
        XCTAssertEqual(body, md)
    }

    func testUnwrapsQuotedValues() {
        let (pairs, _) = MarkdownHTML.splitFrontmatter("---\na: \"double\"\nb: 'single'\nc: bare\n---\n")
        XCTAssertEqual(pairs.map(\.value), ["double", "single", "bare"])
    }

    /// A `|` block scalar puts its text on the following indented lines — the shape the real
    /// Splice files use for `short_description`.
    func testFoldsBlockScalars() {
        let md = """
            ---
            short_description: |
              First line of the description.
              Second line.
            after: yes
            ---
            Body.
            """
        let (pairs, body) = MarkdownHTML.splitFrontmatter(md)
        XCTAssertEqual(pairs.first?.key, "short_description")
        XCTAssertEqual(pairs.first?.value, "First line of the description. Second line.")
        XCTAssertEqual(pairs.last?.key, "after", "the block must end when a new key starts")
        XCTAssertEqual(body, "Body.")
    }

    /// A URL contains a colon; splitting on the LAST one, or on every one, mangles it.
    func testValuesContainingColonsSurvive() {
        let (pairs, _) = MarkdownHTML.splitFrontmatter("---\nurl: \"https://example.com/a:b\"\n---\n")
        XCTAssertEqual(pairs.first?.value, "https://example.com/a:b")
    }

    func testEmptyFrontmatterIsHarmless() {
        let (pairs, body) = MarkdownHTML.splitFrontmatter("---\n---\nBody.")
        XCTAssertTrue(pairs.isEmpty)
        XCTAssertEqual(body, "Body.")
    }

    // MARK: - Rendering

    func testRendersAsATable() {
        let html = MarkdownHTML.render("---\ntitle: Hello\n---\nBody.")
        XCTAssertTrue(html.contains("<table class=\"frontmatter\">"))
        XCTAssertTrue(html.contains("<th>title</th><td>Hello</td>"))
        XCTAssertTrue(html.contains("<p>Body.</p>"))
    }

    /// The bug this exists to prevent: the metadata rendered as one giant heading.
    func testFrontmatterNeverBecomesAHeading() {
        let html = MarkdownHTML.render("---\nslug: x\ntitle: y\n---\nBody.")
        XCTAssertFalse(html.contains("<h2>slug"), "frontmatter leaked into a setext heading: \(html)")
        XCTAssertFalse(html.hasPrefix("<hr>"), "the opening fence leaked as a thematic break")
    }

    func testLinksAreClickable() {
        let html = MarkdownHTML.render("---\nurl: \"https://example.com/x\"\n---\n")
        XCTAssertTrue(html.contains("<a href=\"https://example.com/x\">"))
    }

    /// Frontmatter is data, not markup — a value containing HTML must not become HTML.
    func testValuesAreEscaped() {
        let html = MarkdownHTML.render("---\ntitle: \"<script>alert(1)</script>\"\n---\n")
        XCTAssertFalse(html.contains("<script"), "raw markup leaked from frontmatter: \(html)")
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testDocumentWithoutFrontmatterIsUnchanged() {
        let html = MarkdownHTML.render("# Heading\n\nBody.")
        XCTAssertFalse(html.contains("frontmatter"))
        XCTAssertTrue(html.contains("<h1>Heading</h1>"))
    }
}
