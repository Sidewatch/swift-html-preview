//
//  ArchiveTreeIconTests.swift
//  PreviewViewsTests
//
//  The archive tree gives files the icon their name gives, and drops folder icons as the file tree does.
//
//  Created by David Sherlock on 11/7/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import CodeLanguage
import XCTest

@testable import PreviewViews

@MainActor final class ArchiveTreeIconTests: XCTestCase {
    private var window: NSWindow!

    override func tearDown() {
        window?.orderOut(nil)
        window = nil
        super.tearDown()
    }

    /// An archive of lib/main.swift and notes.md, listed and open in a window.
    private func listed() throws -> ZipArchiveView {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tree-\(UUID().uuidString)")
        let src = dir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try "let a = 1\n".write(to: src.appendingPathComponent("lib/main.swift"), atomically: true, encoding: .utf8)
        try "# Notes\n".write(to: src.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("tree.zip")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        task.arguments = ["-q", "-r", zip.path, "."]
        task.currentDirectoryURL = src
        try task.run(); task.waitUntilExit()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let view = ZipArchiveView()
        window.contentView = view
        view.load(url: zip)
        let started = Date()
        while view.visibleRowCountForTesting < 3, Date().timeIntervalSince(started) < 5 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        window.layoutIfNeeded()
        return view
    }

    func testFilesWearTheIconTheirNameGives() throws {
        let view = try listed()
        XCTAssertEqual(view.entryFactsForTesting("main.swift")?.symbol, Language.symbolName(forFilename: "main.swift"))
        XCTAssertEqual(view.entryFactsForTesting("notes.md")?.symbol, Language.symbolName(forFilename: "notes.md"))
        XCTAssertEqual(view.entryFactsForTesting("lib")?.symbol, "folder")
    }

    func testWithoutFolderIconsTheNamesAtALevelLineUp() throws {
        let view = try listed()
        view.showsFolderIcons = false
        view.layoutSubtreeIfNeeded()
        guard let lib = view.entryFactsForTesting("lib"), let notes = view.entryFactsForTesting("notes.md"),
            let main = view.entryFactsForTesting("main.swift")
        else { return XCTFail("rows missing after the switch") }
        XCTAssertNil(lib.symbol, "a folder has no icon")
        XCTAssertEqual(notes.nameX, lib.nameX, accuracy: 0.5, "a file and a folder at one level start at one x")
        XCTAssertEqual(notes.iconMidX, lib.chevronMidX, accuracy: 1, "the file's icon stands on its level's chevron")
        XCTAssertEqual(main.nameX - notes.nameX, 14, accuracy: 0.5, "one indent a level")
        view.showsFolderIcons = true
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.entryFactsForTesting("lib")?.symbol, "folder", "and back")
        XCTAssertEqual(view.entryFactsForTesting("main.swift") != nil, true, "the folder stays open")
    }
}
