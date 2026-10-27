//
//  CodePreviewViewTests.swift
//  PreviewViewsTests
//
//  The code view builds without typesetting the file.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import CodeLanguage
import XCTest

@testable import PreviewViews

@MainActor final class CodePreviewViewTests: XCTestCase {
    /// A long file is not laid out when the view is built and sized: only what is drawn is. Laid out whole, TextKit 1
    /// typeset every line as the text view sized to fit, before the first draw: 200–300 ms on the main thread for a
    /// thousand lines (Quick Look's budget is 500 ms), seconds at the line cap.
    func testALongFileIsNotLaidOutWhenTheViewIsBuilt() throws {
        let text = (1...3_000).map { "let value\($0) = \($0)  // line \($0) of the file" }.joined(separator: "\n")
        let view = CodePreviewView(text: text, language: .swift)
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        view.layoutSubtreeIfNeeded()
        let layout = try XCTUnwrap(view.textView.layoutManager)
        let length = try XCTUnwrap(view.textView.textStorage?.length)
        XCTAssertLessThan(layout.firstUnlaidCharacterIndex(), length / 10, "the whole file was typeset as the view was built")
        XCTAssertEqual(view.gutter.lineCount, 3_000)
    }
}
