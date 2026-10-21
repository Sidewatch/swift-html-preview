//
//  PageFindScriptTests.swift
//  PreviewViewsTests
//
//  The find script marks exactly the matched text, case-folded without shifting offsets.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
import AppKit
@testable import PreviewViews

/// `PageFindScript`, run in a real sealed page.
@MainActor
final class PageFindScriptTests: XCTestCase {
    private func evaluate(_ script: String, in web: SealedWebView) -> Any? {
        var value: Any?
        var done = false
        web.evaluateJavaScript(script) { result, _ in
            value = result
            done = true
        }
        let deadline = Date(timeIntervalSinceNow: 10)
        while !done, Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        return value
    }

    func testMarksAreTheMatchedTextEvenAfterALetterWhoseLowercaseIsLonger() {
        let web = SealedWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let loaded = expectation(description: "the page loaded")
        web.onLoadFinished = { loaded.fulfill() }
        web.load(html: "<!doctype html><html><body><p>İstanbul has a Kitten and a kit</p></body></html>", baseURL: nil)
        wait(for: [loaded], timeout: 15)
        let count = evaluate(PageFindScript.script(query: "kit", caseSensitive: false, index: 0), in: web) as? Int
        let marked = evaluate("Array.from(document.querySelectorAll('mark.sw-find')).map(m => m.textContent).join('|')", in: web) as? String
        XCTAssertEqual(count, 2)
        XCTAssertEqual(marked, "Kit|kit", "the marks are the matches, not a unit to the right")
        let cased = evaluate(PageFindScript.script(query: "kit", caseSensitive: true, index: nil), in: web) as? Int
        XCTAssertEqual(cased, 1, "case-sensitive: only the lowercase one")
    }

    func testALiteralEscapesWhatWouldEndOrBreakTheString() {
        XCTAssertEqual(PageFindScript.literal("a\"b\\c\nd\u{2028}"), "\"a\\\"b\\\\c\\nd\\u2028\"")
    }
}
