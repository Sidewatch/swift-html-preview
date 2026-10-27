//
//  CSVTableViewTests.swift
//  PreviewViewsTests
//
//  A wide file's grid stops at the column cap and says so.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import XCTest

@testable import PreviewViews

@MainActor final class CSVTableViewTests: XCTestCase {
    /// A CSV `columns` wide, with a header row and two data rows.
    private func csv(columns: Int) -> String {
        let header = (0..<columns).map { "column\($0)" }.joined(separator: ",")
        let row = (0..<columns).map { "\($0)" }.joined(separator: ",")
        return "\(header)\n\(row)\n\(row)\n"
    }

    /// Past the cap the grid builds the first `columnCap` columns (and its "#" column), and the note above it says
    /// how many the file has; each column still shows its own data. Built whole, a 10,000-column file held the main
    /// thread for 43 s.
    func testAWideFileStopsAtTheCapAndSaysSo() throws {
        let cap = CSVTableView.columnCap
        let view = CSVTableView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        view.load(csv(columns: cap + 10_000))
        let table = try XCTUnwrap(view.probeTableView)
        XCTAssertEqual(table.tableColumns.count, cap + 1)
        XCTAssertEqual(table.tableColumns.last?.title, "column\(cap - 1)")
        XCTAssertEqual(view.columnNoteForTesting, "Showing the first \(cap) of \((cap + 10_000).formatted()) columns.")
        XCTAssertEqual(view.probeColumn(cap - 1), ["\(cap - 1)", "\(cap - 1)"])
        XCTAssertEqual(view.shownRowCountForTesting, 2)
        view.layoutSubtreeIfNeeded()
        let grid = try XCTUnwrap(table.enclosingScrollView)
        XCTAssertLessThan(grid.frame.height, view.bounds.height - 10, "the grid starts under the note")
    }

    /// A file within the cap builds every column and shows no note; loading one after a wide file takes the note away.
    func testAFileWithinTheCapShowsEveryColumnAndNoNote() throws {
        let view = CSVTableView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        view.load(csv(columns: CSVTableView.columnCap + 1))
        XCTAssertFalse(view.columnNoteForTesting.isEmpty)
        view.load(csv(columns: 12))
        let table = try XCTUnwrap(view.probeTableView)
        XCTAssertEqual(table.tableColumns.count, 13)
        XCTAssertEqual(view.columnNoteForTesting, "")
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(try XCTUnwrap(table.enclosingScrollView).frame.height, view.bounds.height, "the grid fills the view")
    }
}
