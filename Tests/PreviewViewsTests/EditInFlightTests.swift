//
//  EditInFlightTests.swift
//  PreviewViewsTests
//
//  A reload that arrives while a cell is being edited waits for the edit, and the edit lands on
//  the record it was made on.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
import AppKit
@testable import PreviewViews
import AppKitViews

@MainActor
final class EditInFlightTests: XCTestCase {
    /// A window the view can take the keyboard in; never shown.
    private func host(_ view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        view.frame = window.contentView!.bounds
        window.contentView?.addSubview(view)
        view.layoutSubtreeIfNeeded()
        return window
    }

    /// One run-loop turn: the held-back load is applied after the field editor has let go.
    private func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }

    /// The CSV grid: a load during an edit waits, and the edit is aimed at the record the person
    /// was editing after an outside insert moved it down a row.
    func testACSVLoadDuringAnEditWaitsAndTheEditFollowsItsRecord() throws {
        let view = CSVTableView(frame: .zero)
        let window = host(view)
        view.load("name,qty\napple,1\npear,2\n")
        var edits: [(record: Int, column: Int, value: String)] = []
        view.onEdit = { edits.append(($0, $1, $2)) }
        view.beginEditing(CellPosition(row: 1, tag: 2))
        let editor = try XCTUnwrap(window.fieldEditor(false, for: nil) as? NSTextView, "the pear row's quantity is being edited")
        XCTAssertEqual(editor.string, "2")
        editor.string = "9"
        view.load("name,qty\nplum,0\napple,1\npear,2\n", keepingFilter: true)  // an outside insert above, mid-edit
        XCTAssertTrue(view.hasPendingLoadForTesting)
        XCTAssertEqual(view.shownRowCountForTesting, 2, "the grid waits for the edit")
        window.makeFirstResponder(nil)  // the edit ends
        settle()
        XCTAssertEqual(edits.count, 1, "the typed value was delivered, not dropped")
        XCTAssertEqual(edits.first?.record, 3, "pear is the third record now")
        XCTAssertEqual(edits.first?.column, 1)
        XCTAssertEqual(edits.first?.value, "9")
        XCTAssertEqual(view.shownRowCountForTesting, 3, "the waiting load was applied")
        XCTAssertFalse(view.hasPendingLoadForTesting)
    }

    /// The structure tree: a load during an edit waits; the node's path still names the token.
    func testATreeLoadDuringAnEditWaitsForTheEdit() throws {
        let view = JSONTreeView(frame: .zero)
        _ = host(view)
        view.load(#"{"a": 1, "b": 2}"#)
        var edits: [(path: String, target: JSONTreeView.EditTarget, text: String)] = []
        view.onEdit = { edits.append(($0.path, $1, $2)) }
        XCTAssertEqual(view.beginEditForTesting(path: "$.b", target: .value), "2")
        view.load(#"{"a": 1, "b": 2, "c": 3}"#, keepingExpansion: true)
        XCTAssertTrue(view.hasPendingLoadForTesting)
        XCTAssertEqual(view.visibleRowCountForTesting, 2, "the tree waits for the edit")
        view.typeAndCommitForTesting("7")
        settle()
        XCTAssertEqual(edits.map(\.path), ["$.b"])
        XCTAssertEqual(edits.first?.text, "7")
        XCTAssertEqual(edits.first?.target, .value)
        XCTAssertEqual(view.visibleRowCountForTesting, 3, "the waiting load was applied")
    }
}
