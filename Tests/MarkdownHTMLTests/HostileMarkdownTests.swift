//
//  HostileMarkdownTests.swift
//  MarkdownHTMLTests
//
//  Documents shaped to exhaust the renderer: tens of thousands of nested blockquotes, tens of
//  thousands of math spans, a megabyte of table. Each renders in bounded time and stack.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import MarkdownHTML

final class HostileMarkdownTests: XCTestCase {
    func testFiftyThousandNestedBlockquotesRenderWithoutExhaustingTheStack() {
        let html = MarkdownHTML.render("# Quotes\n\n" + String(repeating: ">", count: 50_000) + " deep\n")
        XCTAssertTrue(html.contains("<blockquote>"), "the quote is still a quote")
        XCTAssertTrue(html.contains("deep"), "the text survives")
        XCTAssertLessThanOrEqual(html.components(separatedBy: "<blockquote>").count - 1, MarkdownHTML.maxBlockquoteDepth)
    }

    func testFiftyThousandMathSpansRestoreInOnePass() {
        let markdown = "# Math\n\n" + String(repeating: "$x_1$ ", count: 50_000) + "\n"
        let started = Date()
        let html = MarkdownHTML.render(markdown)
        let seconds = Date().timeIntervalSince(started)
        XCTAssertEqual(html.components(separatedBy: "<span class=\"math math-inline\">x_1</span>").count - 1, 50_000)
        XCTAssertFalse(html.contains("\u{E000}"), "no placeholder survives")
        XCTAssertLessThan(seconds, 5, "restoring the spans is one pass over the page, not one pass per span")
    }

    func testAMegabyteTableAndALineOfDollarsRenderPromptly() {
        let row = "| alpha | beta | gamma | delta |\n"
        let table = "| a | b | c | d |\n|---|---|---|---|\n" + String(repeating: row, count: (1 << 20) / row.utf8.count)
        let dollars = String(repeating: "$", count: 100_000) + "\n" + String(repeating: "$a ", count: 50_000) + "\n"
        let started = Date()
        let html = MarkdownHTML.render(table + "\n" + dollars)
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }
}
