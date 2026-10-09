//
//  CodePreviewCapTests.swift
//  PreviewViewsTests
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import CodeLanguage
import XCTest

@testable import PreviewViews

@MainActor
final class CodePreviewCapTests: XCTestCase {
    func testAHugeSourceLaysOutOnlyItsFirstLinesAndSaysSo() {
        let text = (1...100_000).map { "let v\($0) = \($0)" }.joined(separator: "\n")
        let started = CFAbsoluteTimeGetCurrent()
        let view = CodePreviewView(text: text, language: .swift)
        let seconds = CFAbsoluteTimeGetCurrent() - started
        XCTAssertEqual(view.gutter.lineCount, CodePreviewCap.lineCap, "only the capped lines are laid out")
        XCTAssertTrue(view.noteForTesting.contains("10,000") && view.noteForTesting.contains("100,000"), view.noteForTesting)
        XCTAssertLessThan(seconds, 6, "a capped preview builds quickly (\(seconds) s)")
    }

    func testASourceUnderTheCapIsShownWholeWithNoNote() {
        let text = (1...50).map { "line \($0)" }.joined(separator: "\n")
        let view = CodePreviewView(text: text, language: .plainText)
        XCTAssertEqual(view.gutter.lineCount, 50)
        XCTAssertEqual(view.noteForTesting, "")
    }

    func testCutKeepsWholeLinesAndCountsTheRest() {
        let cut = CodePreviewCap.cut("a\nb\nc\nd", lineCap: 2)
        XCTAssertEqual(cut.text, "a\nb")
        XCTAssertEqual(cut.totalLines, 4)
        XCTAssertTrue(cut.cut)
        let whole = CodePreviewCap.cut("a\nb", lineCap: 2)
        XCTAssertEqual(whole.text, "a\nb")
        XCTAssertFalse(whole.cut)
    }
}
