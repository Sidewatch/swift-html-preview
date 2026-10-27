//
//  JSONTreeLoadingTests.swift
//  PreviewViewsTests
//
//  A big document read off the main thread: the tree empties and waits, says what it is reading, and the load that
//  follows ends the wait; a structured format reads off the main thread.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import DataConverter
import XCTest

@testable import PreviewViews

@MainActor
final class JSONTreeLoadingTests: XCTestCase {
    func testBeginningALoadEmptiesTheTreeAndTheLoadEndsIt() throws {
        let tree = JSONTreeView()
        tree.load(#"{"old": 1}"#)
        XCTAssertEqual(tree.rootLabelsForTesting, ["old"])
        tree.beginLoading(format: "TOML")
        XCTAssertTrue(tree.isLoading)
        XCTAssertEqual(tree.rootLabelsForTesting, [], "the last document is not shown while the next is read")
        tree.load(structured: try XCTUnwrap(TreeFormat.toml.value(of: "title = \"x\"\n[a]\nb = 1\n", bytes: { nil })), format: "TOML")
        XCTAssertFalse(tree.isLoading, "a structured load ends the wait")
        XCTAssertEqual(tree.rootLabelsForTesting, ["title", "a"])
        tree.beginLoading(format: "JSON")
        tree.load(#"{"new": 2}"#)
        XCTAssertFalse(tree.isLoading, "a JSON load ends it too")
        XCTAssertEqual(tree.rootLabelsForTesting, ["new"])
    }

    /// The readers run on any thread: a document is read on a background queue and arrives whole.
    func testAStructuredFormatReadsOffTheMainThread() async {
        let value = await Task.detached { TreeFormat.yaml.value(of: "a: 1\nb:\n  - x\n", bytes: { nil }) }.value
        XCTAssertNotNil(value)
    }

    /// A document's rows are built off the main thread too (most of a big load), and load as the rows built on it do:
    /// file order, every path, the format's rename rule.
    func testRowsBuiltOffTheMainThreadLoadAsRowsBuiltOnIt() async throws {
        let text = "<a id=\"1\"><z>9</z><b>x</b></a>"
        let value = try XCTUnwrap(TreeFormat.xml.value(of: text, bytes: { nil }))
        let prepared = await Task.detached { JSONTreeView.prepare(value, renamesKey: TreeFormat.xml.renamesKey) }.value
        let offMain = JSONTreeView()
        offMain.load(prepared: prepared, format: "XML", sourceIsEmpty: false)
        let onMain = JSONTreeView()
        onMain.load(structured: value, format: "XML", sourceIsEmpty: false, renamesKey: TreeFormat.xml.renamesKey)
        XCTAssertFalse(offMain.rootLabelsForTesting.isEmpty)
        XCTAssertEqual(offMain.rootLabelsForTesting, onMain.rootLabelsForTesting)
        XCTAssertEqual(offMain.visiblePathsForTesting, onMain.visiblePathsForTesting)
        let element = try XCTUnwrap(prepared.roots.first)
        XCTAssertEqual(element.children.map(\.label), ["@id", "z", "b"], "file order, not sorted")
        XCTAssertEqual(element.children.map(\.renamable), [true, false, false], "XML renames only an attribute")
    }
}
