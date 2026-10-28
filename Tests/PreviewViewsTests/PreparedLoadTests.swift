//
//  PreparedLoadTests.swift
//  PreviewViewsTests
//
//  A big file's CSV grid, `.env` table or schema read off the main thread: beginning the read empties the view and
//  says it is waiting, and what was read on a background queue loads as a read on the main thread does.
//
//  Created by David Sherlock on 10/28/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import XCTest

@testable import PreviewViews

@MainActor
final class PreparedLoadTests: XCTestCase {
    private let frame = NSRect(x: 0, y: 0, width: 700, height: 400)

    /// A CSV read on a background queue: the grid empties and waits, and the rows that land are the rows a read in
    /// place shows, quoting and all.
    func testACSVReadOffTheMainThreadLoadsAsOneReadOnIt() async throws {
        let text = "name,age\nAda,36\n\"Grace, R.\",85\n"
        let prepared = await Task.detached { CSVTableView.prepare(text, tabSeparated: false) }.value
        let view = CSVTableView(frame: frame)
        view.load("old,file\n1,2\n")
        view.beginLoading(format: "CSV")
        XCTAssertTrue(view.isLoading)
        XCTAssertEqual(view.shownRowCountForTesting, 0, "the last file is not shown while the next is read")
        XCTAssertEqual(view.probeTableView?.tableColumns.map(\.title), ["#"])
        view.load(prepared: prepared)
        XCTAssertFalse(view.isLoading, "the load ends the wait")
        let inPlace = CSVTableView(frame: frame)
        inPlace.load(text)
        XCTAssertEqual(view.probeColumn(0), ["Ada", "Grace, R."])
        XCTAssertEqual(view.probeColumn(0), inPlace.probeColumn(0))
        XCTAssertEqual(view.probeTableView?.tableColumns.map(\.title), inPlace.probeTableView?.tableColumns.map(\.title))
    }

    /// A TSV read off the main thread is split on tabs, and the grid knows it (it reads only).
    func testATSVReadOffTheMainThreadSplitsOnTabs() async {
        let prepared = await Task.detached { CSVTableView.prepare("a\tb\n\"x\ty\n", tabSeparated: true) }.value
        let view = CSVTableView(frame: frame)
        view.load(prepared: prepared)
        XCTAssertTrue(view.isTabSeparated)
        XCTAssertEqual(view.probeColumn(0), ["\"x"])
        XCTAssertEqual(view.probeColumn(1), ["y"])
    }

    /// A `.env` read off the main thread keeps its masking: the table empties and waits, then shows every variable
    /// with a secret still bulleted.
    func testAnEnvReadOffTheMainThreadKeepsItsMasking() async {
        let text = "APP_NAME=demo\nAPI_KEY=example-not-a-real-key\n"
        let prepared = await Task.detached { EnvTableView.prepare(text) }.value
        let view = EnvTableView(frame: frame)
        view.load("OLD=1\n")
        view.beginLoading()
        XCTAssertTrue(view.isLoading)
        XCTAssertEqual(view.visibleKeys, [], "the last file is not shown while the next is read")
        view.load(prepared: prepared)
        XCTAssertFalse(view.isLoading)
        XCTAssertEqual(view.visibleKeys, ["APP_NAME", "API_KEY"])
        XCTAssertEqual(view.displayedTextForTesting(row: 0), "demo")
        XCTAssertNotEqual(view.displayedTextForTesting(row: 1), "example-not-a-real-key", "a secret stays masked")
    }

    /// A schema built off the main thread draws its tables; beginning a build takes the last file's away, and the
    /// same schema again only refreshes.
    func testASchemaBuiltOffTheMainThreadShowsItsTables() async {
        let sql =
            "CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT);\n"
            + "CREATE TABLE posts(id INTEGER, user_id INTEGER REFERENCES users(id));\n"
        let prepared = await Task.detached { DatabaseView.prepareSchema(sql) }.value
        let view = DatabaseView(frame: frame)
        view.loadSQL("CREATE TABLE old(x);", key: "old.sql", schemaSource: true)
        XCTAssertEqual(view.tables, ["old"])
        view.beginLoading(format: "SQL")
        XCTAssertTrue(view.isLoading)
        XCTAssertEqual(view.tables, [], "the last file's tables are not shown while the next is built")
        XCTAssertFalse(view.isShowingSchema("CREATE TABLE old(x);", key: "old.sql"))
        view.loadSQL(prepared: prepared, key: "schema.sql", schemaSource: true)
        XCTAssertFalse(view.isLoading)
        XCTAssertEqual(Set(view.tables), ["users", "posts"])
        XCTAssertEqual(view.mode, .diagram)
        XCTAssertTrue(view.isShowingSchema(sql, key: "schema.sql"))
    }
}
