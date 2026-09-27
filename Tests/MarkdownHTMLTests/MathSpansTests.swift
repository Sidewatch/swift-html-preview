//
//  MathSpansTests.swift
//  MarkdownHTMLTests
//
//  `$…$` and `$$…$$` reach the page as math spans with the TeX untouched; dollars in prose,
//  code and fences stay dollars.
//
//  Created by David Sherlock on 9/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import MarkdownHTML

/// Tests for `MathSpans` through `MarkdownHTML.render`.
final class MathSpansTests: XCTestCase {

    func testInlineMathBecomesASpanWithTheTeXUntouched() {
        let html = MarkdownHTML.render("Energy is $E = mc^2$ and $a_1 + b_1$ here.")
        XCTAssertTrue(html.contains("<span class=\"math math-inline\">E = mc^2</span>"), html)
        XCTAssertTrue(html.contains("<span class=\"math math-inline\">a_1 + b_1</span>"), "underscores inside math are not emphasis: \(html)")
        XCTAssertFalse(html.contains("<em>"), html)
    }

    func testDisplayMathMayRunOverLinesAndIsEscaped() {
        let html = MarkdownHTML.render("Before\n\n$$\n\\int_0^1 x\\,dx < 1\n$$\n\nAfter")
        XCTAssertTrue(html.contains("<span class=\"math math-display\">\\int_0^1 x\\,dx &lt; 1</span>"), html)
        XCTAssertTrue(html.contains("<p>Before</p>"))
        XCTAssertTrue(html.contains("<p>After</p>"))
        XCTAssertFalse(html.contains("\u{E000}"), "no placeholder survives")
    }

    func testPricesAreNotMath() {
        let html = MarkdownHTML.render("It costs $5 and $10 today, or $ 20.")
        XCTAssertFalse(html.contains("class=\"math"), html)
        XCTAssertTrue(html.contains("$5 and $10"))
        // A closing dollar followed by a digit is a price, not a delimiter (pandoc's rule).
        XCTAssertFalse(MarkdownHTML.render("from $x$5 up").contains("class=\"math"))
        XCTAssertTrue(MarkdownHTML.render("from $x$ up").contains("class=\"math"))
    }

    func testCodeFencesInlineCodeAndEscapedDollarsAreLeftAlone() {
        let html = MarkdownHTML.render("Use `$x$` in code.\n\n```sh\necho $HOME $PATH $x$ done\n```\n\nA \\$5 note and $y$.")
        XCTAssertTrue(html.contains("<code>$x$</code>"), html)
        XCTAssertTrue(html.contains("echo $HOME $PATH $x$ done"), "a fence's dollars are not math: \(html)")
        XCTAssertTrue(html.contains("$5 note"), html)
        XCTAssertTrue(html.contains("<span class=\"math math-inline\">y</span>"), html)
        XCTAssertEqual(html.components(separatedBy: "class=\"math").count - 1, 1)
    }

    func testAnUnclosedSpanIsProseAndMathCanBeSwitchedOff() {
        XCTAssertFalse(MarkdownHTML.render("A lone $ sign and $unclosed").contains("class=\"math"))
        XCTAssertFalse(MarkdownHTML.render("$$\nnever closed").contains("class=\"math"))
        XCTAssertFalse(MarkdownHTML.render("$E = mc^2$", math: false).contains("class=\"math"))
        XCTAssertTrue(MarkdownHTML.render("$E = mc^2$", math: false).contains("$E = mc^2$"))
    }

    func testMathInsideAListAndAHeadingKeepsItsPlace() {
        let html = MarkdownHTML.render("# Sum $\\sum_i x_i$\n\n- item $a$\n- plain")
        XCTAssertTrue(html.contains("<h1>Sum <span class=\"math math-inline\">\\sum_i x_i</span></h1>"), html)
        XCTAssertTrue(html.contains("item <span class=\"math math-inline\">a</span>"), html)
    }
}
