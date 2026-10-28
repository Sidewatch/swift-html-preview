//
//  MarkdownPreviewHTMLTests.swift
//  PreviewHTMLTests
//
//  The Markdown page's code blocks scroll sideways only under the pointer.
//
//  Created by David Sherlock on 10/28/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest

@testable import PreviewHTML

final class MarkdownPreviewHTMLTests: XCTestCase {
    /// A code block is a scroll container only while the pointer is over it: WebKit gives every scrollable box its own
    /// layer, and a page of 5,000 blocks held the main thread over a second committing them (199 ms clipped).
    func testACodeBlockScrollsOnlyUnderThePointer() {
        let rules = MarkdownPreviewHTML.css.components(separatedBy: "\n")
        let block = rules.first { $0.contains("article pre {") } ?? ""
        XCTAssertTrue(block.contains("overflow-x: hidden"), block)
        XCTAssertTrue(rules.contains { $0.contains("article pre:hover { overflow-x: auto; }") })
    }
}
