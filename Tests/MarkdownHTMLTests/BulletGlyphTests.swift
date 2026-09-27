//
//  BulletGlyphTests.swift
//  MarkdownHTMLTests
//
//  Covers rewriting bullet GLYPHS (`•`, `·`, `▪`…) as real Markdown list markers.
//
//  Created by David Sherlock on 8/6/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import MarkdownHTML

/// Covers rewriting bullet GLYPHS (`•`, `·`, `▪`…) as real Markdown list markers.
///
/// CommonMark recognises only `-`, `*` and `+`, so a run of `• item` lines is one paragraph, and
/// lines inside a paragraph join with spaces — forty items collapse into a single wall of text
/// with bullet separators, which is worse than reading the raw file. Common in exported or
/// scraped documents nobody hand-authored.
///
/// The rewrite has to stay narrow: its whole justification is that it only touches lines already
/// trying to be a list, so the cases proving it leaves other things alone matter more than the
/// ones proving it works.
final class BulletGlyphTests: XCTestCase {

    // MARK: - The fix

    func testBulletLinesBecomeAList() {
        let html = MarkdownHTML.render("Details:\n\n• 250 Claps\n• 450 Hi-Hats\n• 100 Rides\n")
        // Asserting on content and structure, not exact markup: this renderer emits loose list
        // items (`<li><p>…</p></li>`), and pinning the precise tag soup would make the test fail
        // on a formatting change that broke nothing.
        XCTAssertTrue(html.contains("<ul>"), "expected a list, got: \(html)")
        XCTAssertEqual(html.components(separatedBy: "<li>").count - 1, 3, "expected 3 items: \(html)")
        XCTAssertTrue(html.contains("250 Claps"))
        XCTAssertTrue(html.contains("100 Rides"))
        XCTAssertFalse(html.contains("•"), "the glyph should be replaced, not kept: \(html)")
    }

    func testAllRecognisedGlyphs() {
        for glyph in ["•", "·", "▪", "‣", "●", "◦"] {
            let out = MarkdownHTML.normalizeBulletGlyphs("\(glyph) item")
            XCTAssertEqual(out, "- item", "\(glyph) was not rewritten")
        }
    }

    func testIndentationIsPreservedSoNestingSurvives() {
        let out = MarkdownHTML.normalizeBulletGlyphs("• top\n    • nested")
        XCTAssertEqual(out, "- top\n    - nested")
    }

    // MARK: - What it must NOT touch

    /// Inside a fence a bullet is content, not intent — rewriting it would corrupt the code.
    func testLeavesFencedCodeAlone() {
        let md = "```\n• not a list\n```\n"
        XCTAssertEqual(MarkdownHTML.normalizeBulletGlyphs(md), md)
        XCTAssertEqual(MarkdownHTML.normalizeBulletGlyphs("~~~\n• also not\n~~~\n"),
                       "~~~\n• also not\n~~~\n")
    }

    /// Reopening a fence must resume protection, or only the first block is safe.
    func testHandlesMultipleFences() {
        let md = "```\n• one\n```\n• two\n```\n• three\n```"
        let out = MarkdownHTML.normalizeBulletGlyphs(md)
        XCTAssertTrue(out.contains("• one"), "first fence unprotected")
        XCTAssertTrue(out.contains("- two"), "text between fences should be rewritten")
        XCTAssertTrue(out.contains("• three"), "second fence unprotected")
    }

    /// A bullet mid-sentence is punctuation. Only a line that STARTS with one is a list attempt.
    func testLeavesBulletsInsideTextAlone() {
        let md = "Sold in packs • 250 units • royalty free"
        XCTAssertEqual(MarkdownHTML.normalizeBulletGlyphs(md), md)
    }

    /// A glyph with no space after it is not a marker — `•250` is a label, not an item.
    func testRequiresASpaceAfterTheGlyph() {
        XCTAssertEqual(MarkdownHTML.normalizeBulletGlyphs("•250 Claps"), "•250 Claps")
    }

    func testOrdinaryMarkdownIsUntouched() {
        let md = "# Title\n\n- real item\n- another\n\nSome prose.\n"
        XCTAssertEqual(MarkdownHTML.normalizeBulletGlyphs(md), md)
    }

    /// The fast path: a document with no bullet glyph must come back identical.
    func testDocumentWithoutGlyphsIsReturnedUnchanged() {
        let md = "Just prose, no glyphs at all."
        XCTAssertEqual(MarkdownHTML.normalizeBulletGlyphs(md), md)
    }

    /// Hard-wrapped prose is the case the blunter fix (soft break → <br>) would have ruined.
    func testHardWrappedProseStillJoins() {
        let html = MarkdownHTML.render("This paragraph is hard wrapped\nacross two lines.\n")
        XCTAssertTrue(html.contains("hard wrapped across two lines"),
                      "wrapped prose must still join into one line: \(html)")
        XCTAssertFalse(html.contains("<br"))
    }
}
