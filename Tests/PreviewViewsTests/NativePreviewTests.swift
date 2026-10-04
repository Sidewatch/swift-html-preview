//
//  NativePreviewTests.swift
//  PreviewViewsTests
//
//  The native route: each kind of file gets its view, read-only; Markdown and binaries get none.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
import AppKit
import ArchiveIndex
@testable import PreviewViews

@MainActor
final class NativePreviewTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("native-preview-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func file(_ name: String, _ text: String) -> URL {
        let url = dir.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testEachKindTakesItsView() throws {
        XCTAssertEqual(NativePreview.make(fileAt: file("people.tsv", "name\tage\nAda\t36\n"))?.kind, .table)
        XCTAssertEqual(NativePreview.make(fileAt: file("config.yaml", "server:\n  port: 8080\n"))?.kind, .tree)
        XCTAssertEqual(NativePreview.make(fileAt: file("hosts", "127.0.0.1 localhost\n"))?.kind, .records)
        XCTAssertEqual(NativePreview.make(fileAt: file("main.go", "package main\n\nfunc main() {}\n"))?.kind, .code)
        let tree = try XCTUnwrap(NativePreview.make(fileAt: file("app.toml", "[a]\nb = 1\n"))?.view as? JSONTreeView)
        XCTAssertTrue(tree.isReadOnly, "Quick Look never edits")
    }

    func testMarkdownAndBinaryAreNotNative() {
        XCTAssertNil(NativePreview.make(fileAt: file("README.md", "# Title\n")))
        let binary = dir.appendingPathComponent("blob.swift")
        try? Data([0x01, 0x00, 0x02, 0x00]).write(to: binary)
        XCTAssertNil(NativePreview.make(fileAt: binary))
        XCTAssertNil(NativePreview.make(fileAt: dir.appendingPathComponent("missing.swift")))
    }

    /// The code view uses the palette's editor font, colours more than one kind of token, numbers
    /// every line in its gutter, and cannot be edited. (Perl goes through the regex tables: a package
    /// test cannot load the tree-sitter queries from the build, so a grammar language would come out
    /// plain here — the app's --selftest-quicklook covers the grammar tier.)
    func testCodeIsColouredWithAGutter() throws {
        let source = "# A comment\nmy $answer = 42;\nmy $name = \"Ada\";\nsub greet { print $name; }\n"
        let view = try XCTUnwrap(NativePreview.make(fileAt: file("greet.pl", source))?.view as? CodePreviewView)
        XCTAssertFalse(view.textView.isEditable)
        XCTAssertEqual(view.gutter.lineCount, 5)
        XCTAssertGreaterThanOrEqual(view.distinctColorsForTesting(), 3)
        XCTAssertEqual(view.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, PreviewViews.palette.editorFont)
    }

    /// An archive's summary names its kind, files, folders and both sizes — what Space should tell
    /// you before you look at a single row.
    func testArchiveSummaryNamesKindCountsAndSizes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zipsum-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("src/lib"), withIntermediateDirectories: true)
        try String(repeating: "abc ", count: 2_000).write(
            to: dir.appendingPathComponent("src/lib/a.txt"), atomically: true, encoding: .utf8)
        try "hello".write(to: dir.appendingPathComponent("src/readme.txt"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("bundle.zip")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        task.arguments = ["-q", "-r", zip.path, "."]
        task.currentDirectoryURL = dir.appendingPathComponent("src")
        try task.run(); task.waitUntilExit()
        let summary = ZipArchiveView.summary(of: try Archive.listing(at: zip))
        XCTAssertTrue(summary.hasPrefix("Zip · 2 files · 1 folder · "), summary)
        XCTAssertTrue(summary.contains("uncompressed · "), summary)
        XCTAssertTrue(summary.contains("compressed (") && !summary.contains("(0%)"), summary)
    }
}
