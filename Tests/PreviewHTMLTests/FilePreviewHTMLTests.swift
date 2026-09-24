//
//  FilePreviewHTMLTests.swift
//  PreviewHTMLTests
//
//  Each kind through the one entry: a database's tables, a CSV's rows, Markdown's headings,
//  a source file's numbered lines — in the theme's colours, escaped, capped.
//
//  Created by David Sherlock on 9/24/26.
//

import XCTest
@testable import PreviewHTML

@MainActor
final class FilePreviewHTMLTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("preview-html-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }
    private func file(_ name: String, _ text: String) throws -> URL {
        let u = dir.appendingPathComponent(name); try text.write(to: u, atomically: true, encoding: .utf8); return u
    }
    private var theme: ThemeSnapshot {
        ThemeSnapshot(name: "Test", isDark: true, background: "#101010", foreground: "#EEEEEE", comment: "#777777", string: "#A0FFA0", keyword: "#FF66AA",
                      type: "#66CCFF", number: "#FFCC66", function: "#66FFCC", variable: "#EEEEEE", property: "#CCCCFF", accent: "#FF66AA",
                      gutterText: "#555555", statusBackground: "#202020", statusText: "#999999", border: "#333333", added: "#40B050", removed: "#E05050")
    }

    func testCSVBecomesATableWithAHeaderRowAndEscapedCells() throws {
        let u = try file("people.csv", "name,age,note\nAda,36,\"loves <math>\"\nLinus,54,\"says \"\"hi\"\"\"\n")
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: u, theme: theme))
        XCTAssertTrue(html.contains("<th>name</th><th>age</th><th>note</th>"))
        XCTAssertTrue(html.contains("<td>Ada</td><td>36</td><td>loves &lt;math&gt;</td>"))
        XCTAssertTrue(html.contains("says &quot;hi&quot;"))
        XCTAssertTrue(html.contains("CSV · 2 rows"))
        XCTAssertTrue(html.contains("--bg: #101010"), "the theme's page")
    }

    func testTSVSplitsOnTabsAndTheRowCapSaysSo() throws {
        var lines = ["a\tb"]; for i in 0..<600 { lines.append("\(i)\tx") }
        let u = try file("big.tsv", lines.joined(separator: "\n"))
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: u, theme: nil))
        XCTAssertTrue(html.contains("<th>a</th><th>b</th>"))
        XCTAssertTrue(html.contains("Showing the first 500 of 600 rows"))
        XCTAssertFalse(html.contains("<td>599</td>"))
    }

    func testMarkdownIsRenderedWithColouredFences() throws {
        let u = try file("notes.md", "# Title\n\nSome *text*.\n\n```swift\nlet x = 1\n```\n")
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: u, theme: theme))
        XCTAssertTrue(html.contains("<h1"), "rendered, not source")
        XCTAssertTrue(html.contains("<em>text</em>"))
        XCTAssertTrue(html.contains("<article>"))
        XCTAssertTrue(html.contains("Markdown"))
    }

    func testSourceIsNumberedAndEscapedAndWearsTheSnapshot() throws {
        let u = try file("x.unknownext", "a < b && c > d\nsecond")
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: u, theme: theme))
        XCTAssertTrue(html.contains("<td class=\"n\">2</td>"))
        XCTAssertTrue(html.contains("a &lt; b &amp;&amp; c &gt; d"))
        XCTAssertTrue(html.contains("--fg: #EEEEEE"))
        XCTAssertTrue(html.contains("Plain Text") || html.contains("plain"), html.components(separatedBy: "\n").prefix(16).last ?? "")
    }

    func testAFilePastTheCapShowsItsFirstPartAndSaysSo() throws {
        let u = dir.appendingPathComponent("huge.txt")
        try Data(count: FilePreviewHTML.byteCap + 5_000).write(to: u)
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: u, theme: nil))
        XCTAssertTrue(html.contains("Showing the first 1 MB"))
    }

    func testAnUnreadablePathRendersNothing() {
        XCTAssertNil(FilePreviewHTML.render(fileAt: dir.appendingPathComponent("missing.swift"), theme: nil))
    }

    /// A database is known by its header, whatever the name: tables, columns, counts, rows.
    func testASQLiteDatabaseShowsItsTables() throws {
        let u = dir.appendingPathComponent("shop.data")   // not .db on purpose: the header decides
        let sqlite = Process(); sqlite.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        sqlite.arguments = [u.path, "CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT NOT NULL); INSERT INTO users(name) VALUES ('Ada'),('<b>Linus</b>'); CREATE TABLE empty(x TEXT);"]
        try sqlite.run(); sqlite.waitUntilExit()
        XCTAssertEqual(sqlite.terminationStatus, 0)
        XCTAssertTrue(DatabasePreviewHTML.isSQLite(try Data(contentsOf: u)))
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: u, theme: theme))
        XCTAssertTrue(html.contains("SQLite · 2 tables"))
        XCTAssertTrue(html.contains("users <span class=\"count\">2 rows</span>"))
        XCTAssertTrue(html.contains("🔑 id <i>INTEGER</i>"))
        XCTAssertTrue(html.contains("name <i>TEXT not null</i>"))
        XCTAssertTrue(html.contains("<td>&lt;b&gt;Linus&lt;/b&gt;</td>"), "cells are escaped")
        XCTAssertTrue(html.contains("empty <span class=\"count\">0 rows</span>"))
    }

    func testThemeSnapshotRoundTripsAndHexes() throws {
        let u = dir.appendingPathComponent("theme.json")
        try theme.write(to: u)
        XCTAssertEqual(ThemeSnapshot.load(from: u), theme)
        XCTAssertEqual(ThemeSnapshot.hex(NSColor(srgbRed: 1, green: 0.4, blue: 2.0 / 3, alpha: 1)), "#FF66AA")
        XCTAssertNil(ThemeSnapshot.load(from: dir.appendingPathComponent("none.json")))
        XCTAssertTrue(ThemeSnapshot.defaultURL.path.hasSuffix("/Library/Application Support/Sidewatch/quicklook-theme.json"))
    }
}
