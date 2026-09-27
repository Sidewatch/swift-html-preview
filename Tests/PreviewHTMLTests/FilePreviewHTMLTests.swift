//
//  FilePreviewHTMLTests.swift
//  PreviewHTMLTests
//
//  Each kind through the one entry: a database's tables, a CSV's rows, Markdown's headings,
//  a source file's numbered lines — in the theme's colours, escaped, capped.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
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

    /// A shell tool run for a fixture (the system's zip / tar / sqlite3), from `cwd`.
    func run(_ tool: String, _ args: [String], cwd: URL? = nil) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        p.currentDirectoryURL = cwd
        p.environment = ["COPYFILE_DISABLE": "1", "PATH": "/usr/bin:/bin"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, tool)
    }

    func testCSVBecomesAFilteredTableWithAHeaderRowAndEscapedCells() throws {
        let u = try file("people.csv", "name,age,note\nAda,36,\"loves <math>\"\nLinus,54,\"says \"\"hi\"\"\"\n")
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: u, theme: theme))
        XCTAssertTrue(html.contains("<th>name</th><th>age</th><th>note</th>"))
        XCTAssertTrue(html.contains("<tr class=\"row\"><td class=\"num\">1</td><td>Ada</td><td>36</td><td>loves &lt;math&gt;</td>"), "rows carry the class the filter walks")
        XCTAssertTrue(html.contains("says &quot;hi&quot;"))
        XCTAssertTrue(html.contains("CSV · 2 rows"))
        XCTAssertTrue(html.contains("<input class=\"filter\" type=\"search\" placeholder=\"Filter rows\""), "the bar holds a filter field")
        XCTAssertTrue(html.contains("<script>") && html.contains("f.addEventListener('input', apply)"), "the filter script rides the page")
        XCTAssertTrue(html.contains("--bg: #101010"), "the theme's page")
        XCTAssertFalse(html.contains("class=\"strip\""), "no title strip: Quick Look shows the name")
        XCTAssertTrue(html.contains("<title>people.csv</title>"))
    }

    func testTSVSplitsOnTabsAndTheRowCapSaysSo() throws {
        var lines = ["a\tb"]; for i in 0..<600 { lines.append("\(i)\tx") }
        let u = try file("big.tsv", lines.joined(separator: "\n"))
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: u, theme: nil))
        XCTAssertTrue(html.contains("<th>a</th><th>b</th>"))
        XCTAssertTrue(html.contains("TSV · 600 rows · first 500"))
        XCTAssertFalse(html.contains("<td>599</td>"))
    }

    func testMarkdownIsRenderedWithColouredFences() throws {
        let u = try file("notes.md", "# Title\n\nSome *text*.\n\n```scss\n$primary: #336699;\n```\n")
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: u, theme: theme))
        XCTAssertTrue(html.contains("<h1"), "rendered, not source")
        XCTAssertTrue(html.contains("<em>text</em>"))
        XCTAssertTrue(html.contains("<article>"))
        XCTAssertTrue(html.contains("<span style=\"color:"), "an SCSS fence is coloured through the regex tier — it has no grammar")
        XCTAssertFalse(html.contains("class=\"strip\""))
    }

    func testSourceIsNumberedAndEscapedAndWearsTheSnapshot() throws {
        let u = try file("x.unknownext", "a < b && c > d\nsecond")
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: u, theme: theme))
        XCTAssertTrue(html.contains("<td class=\"n\">2</td>"))
        XCTAssertTrue(html.contains("a &lt; b &amp;&amp; c &gt; d"))
        XCTAssertTrue(html.contains("--fg: #EEEEEE"))
        XCTAssertFalse(html.contains("<span style=\"color:"), "plain text has no colour runs")
    }

    /// SCSS has no vendored grammar; the page colours it the way the editor does, through the
    /// regex tables.
    func testALanguageWithoutAGrammarIsColoured() throws {
        let u = try file("tokens.scss", "// Design tokens\n$primary: #336699;\n@mixin flex($dir: row) { display: flex; }\n")
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: u, theme: theme))
        XCTAssertTrue(html.contains("<span style=\"color:#777777\">// Design tokens</span>"), "the comment wears the snapshot's comment colour: \(html.suffix(600))")
        XCTAssertTrue(html.contains("<td class=\"n\">3</td>"))
    }

    /// TypeScript's `.ts` is also MPEG-2's, and the extension claims that type: a real stream
    /// (NUL bytes in its first block) gets no page; TypeScript source gets its page.
    func testBinaryBytesGetNoPageAndTypeScriptDoes() throws {
        var stream = Data(); for _ in 0..<4 { stream.append(0x47); stream.append(Data(repeating: 0, count: 187)) }
        try stream.write(to: dir.appendingPathComponent("video.ts"))
        XCTAssertTrue(FilePreviewHTML.looksBinary(stream))
        XCTAssertNil(FilePreviewHTML.render(fileAt: dir.appendingPathComponent("video.ts"), theme: nil))
        let ts = try file("app.ts", "const greet = (name: string): string => `hi ${name}`;\n")
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: ts, theme: theme))
        XCTAssertTrue(html.contains("<table class=\"code\">") && html.contains("greet"))
    }

    func testAFilePastTheCapShowsItsFirstPartAndSaysSo() throws {
        let u = dir.appendingPathComponent("huge.txt")
        try Data(repeating: 0x61, count: FilePreviewHTML.byteCap + 5_000).write(to: u)
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: u, theme: nil))
        XCTAssertTrue(html.contains("Showing the first 1 MB"))
    }

    func testAnUnreadablePathRendersNothing() {
        XCTAssertNil(FilePreviewHTML.render(fileAt: dir.appendingPathComponent("missing.swift"), theme: nil))
    }

    /// A database is known by its header, whatever the name: one TAB per table (CSS radios, no
    /// script), each with its columns, its count and its rows, the filter over them all.
    func testASQLiteDatabaseShowsItsTablesAsTabs() throws {
        let u = dir.appendingPathComponent("shop.data")   // not .db on purpose: the header decides
        try run("/usr/bin/sqlite3", [u.path, "CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT NOT NULL); INSERT INTO users(name) VALUES ('Ada'),('<b>Linus</b>'); CREATE TABLE empty(x TEXT);"])
        XCTAssertTrue(DatabasePreviewHTML.isSQLite(try Data(contentsOf: u)))
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: u, theme: theme))
        XCTAssertTrue(html.contains("<input class=\"tab\" type=\"radio\" name=\"tab\" id=\"tab0\" checked>"), "the first table's tab is chosen")
        XCTAssertTrue(html.contains("<input class=\"tab\" type=\"radio\" name=\"tab\" id=\"tab1\">"))
        XCTAssertTrue(html.contains("<label for=\"tab0\">empty<span class=\"n\">0</span></label>"), "tables in name order, each tab counting its rows")
        XCTAssertTrue(html.contains("<label for=\"tab1\">users<span class=\"n\">2</span></label>"))
        XCTAssertTrue(html.contains("<section class=\"panel\" id=\"p0\">") && html.contains("<section class=\"panel\" id=\"p1\">"))
        XCTAssertTrue(html.contains("#tab1:checked ~ #p1 { display: block; }"), "the radio shows its panel with no script")
        XCTAssertTrue(html.contains("<b>⚿</b> id <i>INTEGER</i>"))
        XCTAssertTrue(html.contains("name <i>TEXT not null</i>"))
        XCTAssertTrue(html.contains("<tr class=\"row\"><td>2</td><td>&lt;b&gt;Linus&lt;/b&gt;</td></tr>"), "cells are escaped, rows filterable")
        XCTAssertTrue(html.contains("input.filter"))
        XCTAssertFalse(html.contains("class=\"strip\""))
        XCTAssertFalse(html.contains("SQLite · "), "the kind line went with the strip")
    }

    /// A zip is known by its signature: its members as a tree, folders first, with sizes and a
    /// filter over the paths; a tar the same. Nothing is unpacked.
    func testAnArchiveShowsItsTree() throws {
        let src = dir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src.appendingPathComponent("lib/deep"), withIntermediateDirectories: true)
        try "hello".write(to: src.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        try String(repeating: "x", count: 2_500).write(to: src.appendingPathComponent("lib/deep/big.txt"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("bundle.vsix")   // a zip by any name
        try run("/usr/bin/zip", ["-q", "-r", zip.path, "."], cwd: src)
        let html = try XCTUnwrap(FilePreviewHTML.render(fileAt: zip, theme: theme))
        XCTAssertTrue(html.contains("Zip · 2 files · 2 folders · 2.5 KB uncompressed"), html.components(separatedBy: "\n").first { $0.contains("class=\"bar\"") } ?? "")
        XCTAssertTrue(html.contains("<tr class=\"row folder\"><td class=\"name\"><span class=\"d\" style=\"width:0px\"></span>lib<span class=\"path\" hidden>lib</span></td>"))
        XCTAssertTrue(html.contains("<span class=\"d\" style=\"width:32px\"></span>big.txt<span class=\"path\" hidden>lib/deep/big.txt</span></td><td class=\"size\">2.5 KB</td>"), "two levels in, with its size")
        XCTAssertTrue(html.contains("readme.txt"))
        XCTAssertTrue(html.range(of: "lib<span")!.lowerBound < html.range(of: "readme.txt<span")!.lowerBound, "folders first")
        XCTAssertTrue(html.contains("placeholder=\"Filter by path\""))
        let tar = dir.appendingPathComponent("bundle.tar")
        try run("/usr/bin/tar", ["-cf", tar.path, "."], cwd: src)
        let tarHTML = try XCTUnwrap(FilePreviewHTML.render(fileAt: tar, theme: nil))
        XCTAssertTrue(tarHTML.contains("Tar · 2 files"), tarHTML.components(separatedBy: "\n").first { $0.contains("class=\"bar\"") } ?? "")
        XCTAssertTrue(tarHTML.contains("big.txt"))
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
