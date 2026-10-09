//
//  DatabasePreviewHTMLTests.swift
//  PreviewHTMLTests
//
//  A render opens the database read-only and leaves nothing beside it; a WAL database without its
//  sidecars still renders.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import PreviewHTML

final class DatabasePreviewHTMLTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("dbhtml-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? fm.removeItem(at: dir) }

    private func database(_ name: String, _ sql: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = [url.path, sql]
        try p.run()
        p.waitUntilExit()
        return url
    }

    func testARenderLeavesNoJournalBesideARollbackDatabase() throws {
        let url = try database("plain.db", "CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT); INSERT INTO items(name) VALUES ('a');")
        let before = try fm.contentsOfDirectory(atPath: dir.path)
        let body = try XCTUnwrap(DatabasePreviewHTML.body(databaseAt: url))
        XCTAssertTrue(body.contains("items"))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.path), before)
    }

    func testAWALDatabaseWithoutItsSidecarsStillRenders() throws {
        let url = try database(
            "journal.db",
            "PRAGMA journal_mode=WAL; CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT); INSERT INTO items(name) VALUES ('a');")
        try? fm.removeItem(at: dir.appendingPathComponent("journal.db-shm"))
        try? fm.removeItem(at: dir.appendingPathComponent("journal.db-wal"))
        // A read-only connection cannot read a WAL database whose sidecars are missing (CANTOPEN),
        // so the render falls back to a read-write connection for that one case.
        let body = try XCTUnwrap(DatabasePreviewHTML.body(databaseAt: url))
        XCTAssertTrue(body.contains("items"), body)
    }
}
