//
//  SchemaDiagramViewTests.swift
//  PreviewViewsTests
//
//  A diagram's redraw paints only the boxes it crosses.
//
//  Created by David Sherlock on 10/28/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import SQLiteReader
import XCTest

@testable import PreviewViews

@MainActor final class SchemaDiagramViewTests: XCTestCase {
    /// A redraw of the top-left corner paints the few boxes there, not all two hundred: drawing every box and every
    /// column's name on each pass held the main thread 1.3 s a redraw at 426 tables.
    func testARedrawPaintsOnlyTheBoxesItCrosses() throws {
        let sql = (0..<200).map {
            "CREATE TABLE t\($0) (id INTEGER PRIMARY KEY, name TEXT, parent INTEGER REFERENCES t\(max(0, $0 - 1))(id));"
        }
        .joined(separator: "\n")
        let db = try XCTUnwrap(SQLiteDB(sql: sql))
        let view = SchemaDiagramView(frame: .zero)
        view.load(db, tables: db.tables())
        let corner = NSRect(x: 0, y: 0, width: 400, height: 300)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: corner))
        view.cacheDisplay(in: corner, to: rep)
        XCTAssertGreaterThan(view.boxesDrawnForTesting, 0, "the boxes in the corner are drawn")
        XCTAssertLessThan(view.boxesDrawnForTesting, 10, "and only those: \(view.boxesDrawnForTesting) of 200")
    }
}
