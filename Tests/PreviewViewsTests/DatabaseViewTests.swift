//
//  DatabaseViewTests.swift
//  PreviewViewsTests
//
//  The browser opens a database read-only, reopens read-write on the first write, deletes rows in
//  one transaction, and reads a WAL database without leaving files beside it.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
import AppKit
import SQLiteReader
@testable import PreviewViews

@MainActor
final class DatabaseViewTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default
    private let schema = "CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT); INSERT INTO items(name) VALUES ('a'), ('b'), ('c');"

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("dbview-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? fm.removeItem(at: dir) }

    /// A database built with the system's `sqlite3`.
    private func database(_ name: String, _ sql: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = [url.path, sql]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        return url
    }

    /// A browser in a window it can take the keyboard in; never shown.
    private func browser() -> DatabaseView {
        let view = DatabaseView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(view)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func names(_ url: URL) -> [String] {
        SQLiteDB(url: url, readOnly: true)?.run("SELECT name FROM items ORDER BY id").rows.compactMap(\.first) ?? []
    }

    func testBrowsingOpensReadOnlyAndTheFirstEditReopensReadWrite() throws {
        let url = try database("shop.db", schema)
        let view = browser()
        view.load(url)
        XCTAssertEqual(view.db?.readOnly, true, "browsing never opens for writing")
        XCTAssertEqual(view.editableTable, "items", "the grid is editable: the file is writable, whatever the connection")
        view.commitEditForTesting(row: 0, col: 1, text: "apple")
        XCTAssertEqual(view.db?.readOnly, false, "the first write reopened read-write")
        XCTAssertEqual(names(url), ["apple", "b", "c"])
    }

    func testDeleteRowIsOneTransactionAndKeepsTheError() throws {
        let url = try database(
            "guarded.db",
            schema + " CREATE TRIGGER keep_first BEFORE DELETE ON items WHEN OLD.id = 1 BEGIN SELECT RAISE(ABORT, 'first row stays'); END;")
        let view = browser()
        view.load(url)
        view.resultsTable.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
        let saved = DatabaseView.confirmDelete
        DatabaseView.confirmDelete = { _, _ in true }
        defer { DatabaseView.confirmDelete = saved }
        view.deleteSelectedRows()
        XCTAssertEqual(names(url), ["a", "b", "c"], "the row deleted before the refused one is rolled back")
        XCTAssertTrue(view.statusLabel.stringValue.contains("first row stays"), view.statusLabel.stringValue)
        XCTAssertEqual(view.result.rows.count, 3, "the grid still shows every row")
    }

    func testATypedStatementThatCanLoseDataIsConfirmedAndRunsReadWrite() throws {
        let url = try database("typed.db", schema)
        let view = browser()
        view.load(url)
        let saved = DatabaseView.confirmWrite
        defer { DatabaseView.confirmWrite = saved }
        var asked: [String] = []
        DatabaseView.confirmWrite = {
            asked.append($0); return false
        }
        view.queryView.string = "DELETE FROM items WHERE id = 3"
        view.runQuery()
        XCTAssertEqual(asked, ["DELETE FROM items"])
        XCTAssertEqual(names(url), ["a", "b", "c"], "Cancel runs nothing")
        XCTAssertEqual(view.db?.readOnly, true)
        DatabaseView.confirmWrite = { _ in true }
        view.runQuery()
        XCTAssertEqual(names(url), ["a", "b"])
        XCTAssertEqual(view.db?.readOnly, false)
    }

    func testAWALDatabaseIsBrowsedWithoutNewFilesAndReadWhenItsSidecarsAreMissing() throws {
        let url = try database("journal.db", "PRAGMA journal_mode=WAL; " + schema)
        let before = Set(try fm.contentsOfDirectory(atPath: dir.path))
        XCTAssertTrue(before.contains("journal.db-shm"), "sqlite3 leaves the sidecars beside the file on this OS: \(before)")
        let view = browser()
        view.load(url)
        XCTAssertEqual(view.db?.readOnly, true)
        XCTAssertEqual(view.tables, ["items"])
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: dir.path)), before, "a read-only browse creates nothing")
        // Without its sidecars a WAL database cannot be read by a read-only connection at all
        // (CANTOPEN), so the open falls back to read-write, which creates them.
        view.db = nil  // the browsing connection goes first; the sidecars are deleted under no open connection
        try fm.removeItem(at: dir.appendingPathComponent("journal.db-shm"))
        try fm.removeItem(at: dir.appendingPathComponent("journal.db-wal"))
        let fresh = browser()
        fresh.load(url)
        XCTAssertEqual(fresh.tables, ["items"], "the fallback read the database")
        XCTAssertEqual(fresh.db?.readOnly, false)
    }
}
