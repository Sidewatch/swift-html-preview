//
//  EmptyStatesTests.swift
//  PreviewViewsTests
//
//  Every preview says what it has nothing to show for: empty, unreadable, or filtered away — and a
//  cleared filter puts the file's own state back.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
import AppKit
import ArchiveIndex
@testable import PreviewViews

/// The empty states of the trees, the CSV grid and the archive list.
@MainActor
final class EmptyStatesTests: XCTestCase {
    /// The text a person sees: every non-empty label not inside a hidden view.
    private func shown(_ view: NSView) -> [String] {
        func visible(_ v: NSView) -> Bool {
            var cursor: NSView? = v
            while let node = cursor {
                if node.isHidden { return false }
                cursor = node.superview
            }
            return true
        }
        var out: [String] = []
        func walk(_ v: NSView) {
            if let field = v as? NSTextField, visible(field), !field.stringValue.isEmpty { out.append(field.stringValue) }
            v.subviews.forEach(walk)
        }
        walk(view)
        return out
    }

    func testAClearedFilterPutsBackTheFilesOwnState() {
        let tree = JSONTreeView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        tree.load("{ broken")
        XCTAssertTrue(shown(tree).contains("Invalid JSON"))
        tree.filter("x", caseSensitive: false)
        XCTAssertTrue(shown(tree).contains("Invalid JSON"), "nothing to filter: the real cause stays, not No Matches")
        tree.filter("", caseSensitive: false)
        XCTAssertTrue(shown(tree).contains("Invalid JSON"), "a cleared filter puts it back")
        tree.load("{\"name\": \"Acme\"}")
        tree.filter("zzz", caseSensitive: false)
        XCTAssertTrue(shown(tree).contains("No Matches"))
        tree.filter("", caseSensitive: false)
        XCTAssertFalse(tree.emptyStateShownForTesting, "rows again: no empty state")
    }

    func testAStructuredFileWithTextItCannotReadIsNotEmpty() {
        let tree = JSONTreeView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        tree.load(structured: nil, format: "Property List", sourceIsEmpty: false)
        XCTAssertTrue(shown(tree).contains("Couldn't Read Property List"), "\(shown(tree))")
        tree.load(structured: nil, format: "YAML", sourceIsEmpty: true)
        XCTAssertTrue(shown(tree).contains("Empty YAML"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("broken-\(UUID().uuidString).plist")
        try? "this is not a property list".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let made = NativePreview.make(fileAt: url)
        XCTAssertTrue(made.map { shown($0.view).contains("Couldn't Read Property List") } ?? false, "Quick Look says it too")
    }

    func testAHeaderOnlyCSVSaysItHasNoRows() {
        let grid = CSVTableView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        grid.load("name,age\n")
        XCTAssertTrue(shown(grid).contains("No Rows"), "\(shown(grid))")
        grid.load("")
        XCTAssertTrue(shown(grid).contains("Empty CSV"))
        grid.load("name,age\nAda,36\n")
        XCTAssertFalse(grid.emptyStateShownForTesting)
    }

    func testAnArchiveSaysWhetherItIsEmptyOrUnreadable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archives-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let broken = dir.appendingPathComponent("broken.zip")
        try Data("PK\u{3}\u{4}not really a zip".utf8).write(to: broken)
        let empty = dir.appendingPathComponent("empty.zip")
        // The end-of-central-directory record alone: a valid zip with no entries.
        try Data([0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 18)).write(to: empty)
        for (url, title) in [(broken, "Couldn't Read Archive"), (empty, "Empty Archive")] {
            let view = ZipArchiveView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
            view.load(url: url)
            let deadline = Date(timeIntervalSinceNow: 5)
            while view.emptyStateTitleForTesting.isEmpty, Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
            XCTAssertEqual(view.emptyStateTitleForTesting, title, url.lastPathComponent)
        }
    }
}
