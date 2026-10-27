//
//  TableCopyingTests.swift
//  PreviewViewsTests
//
//  What every preview table copies: typed database rows, every field of a CSV record, records with their empty cells,
//  .env values hidden while hidden, a tree node's jq path.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import DataConverter
import SQLiteReader
import XCTest

@testable import PreviewViews

@MainActor
final class TableCopyingTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("copying-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    /// A database built with the system's `sqlite3`.
    private func database(_ sql: String) throws -> URL {
        let url = dir.appendingPathComponent("shop.db")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = [url.path, sql]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        return url
    }

    /// A browser in a window; never shown.
    private func browser() -> DatabaseView {
        let view = DatabaseView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(view)
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// A browsed table's rows copy with their types (a real NULL apart from the text "NULL", numbers as numbers) and
    /// as INSERT statements; the menu names them, then Delete. A view's rows copy too, with nothing to insert into and
    /// nothing to delete; a typed query's have no table to insert into.
    func testDatabaseRowsCopyTypedAndAsInsertsWhereThereIsATable() throws {
        let view = browser()
        view.load(
            try database(
                """
                CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT, score REAL, note TEXT);
                INSERT INTO t VALUES (1, 'NULL', 2.5, NULL), (2, 'b', NULL, 'x');
                CREATE VIEW v AS SELECT * FROM t;
                """))
        view.selectTable("t")
        view.resultsTable.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
        XCTAssertEqual(
            view.copier.text(.json),
            """
            [
              {
                "id": 1,
                "name": "NULL",
                "score": 2.5,
                "note": null
              },
              {
                "id": 2,
                "name": "b",
                "score": null,
                "note": "x"
              }
            ]

            """)
        XCTAssertEqual(
            view.copier.text(.sqlInsert),
            """
            INSERT INTO "t" ("id", "name", "score", "note") VALUES (1, 'NULL', 2.5, NULL);
            INSERT INTO "t" ("id", "name", "score", "note") VALUES (2, 'b', NULL, 'x');

            """)
        view.menuNeedsUpdate(view.resultsMenu)
        XCTAssertEqual(
            view.resultsMenu.items.map(\.title).filter { !$0.isEmpty },
            ["Copy 2 Rows", "Copy as JSON", "Copy as CSV", "Copy as Markdown Table", "Copy as SQL INSERT", "Delete 2 Rows"])

        view.selectTable("v")
        view.resultsTable.selectRowIndexes(IndexSet([0]), byExtendingSelection: false)
        view.menuNeedsUpdate(view.resultsMenu)
        XCTAssertEqual(view.resultsMenu.items.map(\.title), ["Copy Row", "Copy as JSON", "Copy as CSV", "Copy as Markdown Table"])

        view.selectTable("t")
        view.queryView.string = "SELECT name, score FROM t"
        view.runQuery()
        view.resultsTable.selectRowIndexes(IndexSet([1]), byExtendingSelection: false)
        XCTAssertNil(view.copier.text(.sqlInsert), "a typed query's rows have no table to insert into")
        XCTAssertEqual(view.copier.text(.csv), "name,score\nb,\n")
    }

    /// The tables list and the diagram offer a table's name and the SQL that made it.
    func testATablesMenuOffersItsNameAndCreateStatement() throws {
        let view = browser()
        view.load(try database("CREATE TABLE t(id INTEGER PRIMARY KEY); CREATE INDEX t_id ON t(id);"))
        XCTAssertEqual(view.tableMenu(for: "t").items.map(\.title), ["Copy Name", "Copy CREATE Statement"])
        XCTAssertEqual(view.db?.createStatements(for: "t"), ["CREATE TABLE t(id INTEGER PRIMARY KEY);", "CREATE INDEX t_id ON t(id);"])
    }

    /// A CSV record copies whole, empty fields in their places.
    func testCSVRowsCopyEveryField() throws {
        let view = CSVTableView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        view.load("a,b,c\n1,,3\n4,5,6\n")
        try XCTUnwrap(view.probeTableView).selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
        XCTAssertEqual(view.copier.text(.rows), "1\t\t3\n4\t5\t6\n")
        XCTAssertEqual(view.copier.text(.markdown), "| a | b | c |\n| --- | --- | --- |\n| 1 |  | 3 |\n| 4 | 5 | 6 |\n")
    }

    /// A record copies with its empty cells in their places (Copy Row used to drop them, shifting every column after)
    /// and whether it is on.
    func testRecordRowsKeepTheirEmptyCellsAndSayWhetherTheyAreOn() {
        let view = RecordTableView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        view.load(RecordFormat.hosts.table("127.0.0.1 localhost\n# 0.0.0.0 ads.example.com # ad server\n"))
        view.selectRowsForTesting([0, 1])
        XCTAssertEqual(
            view.copier.text(.csv),
            "Address,Host Names,tags,Comment,Enabled\n127.0.0.1,localhost,,,true\n0.0.0.0,ads.example.com,blocked,ad server,false\n")
        XCTAssertEqual(view.copier.text(.rows)?.components(separatedBy: "\n").first, "127.0.0.1\tlocalhost\t\t\ttrue")
    }

    /// A hidden value copies as its bullets until Show values is on.
    func testEnvRowsKeepHiddenValuesHidden() {
        let view = EnvTableView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        view.load("API_SECRET=example-not-a-real-secret\nNAME=demo\n")
        view.selectRowsForTesting([0, 1])
        XCTAssertEqual(view.copier.text(.rows), "API_SECRET\t\(DotEnv.mask)\nNAME\tdemo\n")
        view.setRevealForTesting(true)
        view.selectRowsForTesting([0, 1])
        XCTAssertEqual(view.copier.text(.rows), "API_SECRET\texample-not-a-real-secret\nNAME\tdemo\n")
    }

    /// A tree node's menu offers its jq path beside its JSONPath.
    func testATreeNodeOffersItsJQPath() {
        let tree = JSONTreeView()
        tree.load(#"{"users": [{"name": "x"}]}"#)
        XCTAssertEqual(Array(tree.menuTitlesForTesting(row: 0).prefix(2)), ["Copy Path", "Copy jq Path"])
    }
}
