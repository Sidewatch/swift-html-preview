//
//  SQLStatementKindTests.swift
//  PreviewViewsTests
//
//  Reads run as they are, writes need the read-write connection, destructive statements are asked about.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import PreviewViews

final class SQLStatementKindTests: XCTestCase {
    func testReadsWritesAndDestructiveStatementsByTheirVerbs() {
        XCTAssertEqual(SQLStatementKind.of(script: "SELECT * FROM users"), .read)
        XCTAssertEqual(SQLStatementKind.of(script: "-- note\n  select 1;"), .read)
        XCTAssertEqual(SQLStatementKind.of(script: "/* c */ EXPLAIN QUERY PLAN SELECT 1"), .read)
        XCTAssertEqual(SQLStatementKind.of(script: "PRAGMA journal_mode"), .read)
        XCTAssertEqual(SQLStatementKind.of(script: "PRAGMA journal_mode = DELETE"), .write, "a pragma with a value changes the file")
        XCTAssertEqual(SQLStatementKind.of(script: "INSERT INTO users(name) VALUES ('x')"), .write)
        XCTAssertEqual(SQLStatementKind.of(script: "CREATE TABLE t(a)"), .write)
        XCTAssertEqual(SQLStatementKind.of(script: "DELETE FROM users WHERE id = 1"), .destructive)
        XCTAssertEqual(SQLStatementKind.of(script: "update users set name = 'y'"), .destructive)
        XCTAssertEqual(SQLStatementKind.of(script: "DROP TABLE users"), .destructive)
        XCTAssertEqual(SQLStatementKind.of(script: "SELECT 1; DROP TABLE users"), .destructive, "the strongest statement decides")
    }

    func testACommonTableExpressionIsJudgedByItsVerb() {
        XCTAssertEqual(SQLStatementKind.of(script: "WITH t AS (SELECT 1 AS a) SELECT a FROM t"), .read)
        XCTAssertEqual(
            SQLStatementKind.of(script: "WITH old AS (SELECT id FROM users WHERE x) DELETE FROM users WHERE id IN (SELECT id FROM old)"),
            .destructive)
        XCTAssertEqual(
            SQLStatementKind.of(
                script: "WITH RECURSIVE c(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM c WHERE n < 3) INSERT INTO t SELECT n FROM c"), .write
        )
    }

    func testTheSummaryNamesTheVerbAndObject() {
        XCTAssertEqual(SQLStatementKind.summary(of: "delete from users where id = 1"), "DELETE from users")
        XCTAssertEqual(SQLStatementKind.summary(of: "SELECT 1;\nDROP TABLE users;"), "DROP TABLE users")
        XCTAssertEqual(SQLStatementKind.summary(of: "UPDATE users SET a = 1"), "UPDATE users SET")
    }
}
