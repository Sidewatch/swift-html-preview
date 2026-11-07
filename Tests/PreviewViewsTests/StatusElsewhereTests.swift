//
//  StatusElsewhereTests.swift
//  PreviewViewsTests
//
//  A host that shows a view's status itself gets the words, and the view keeps no line for them.
//
//  Created by David Sherlock on 11/7/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import XCTest

@testable import PreviewViews

@MainActor final class StatusElsewhereTests: XCTestCase {
    private func laidOut<V: NSView>(_ view: V) -> V {
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func testAnArchiveSaysItsSummaryToTheHostAndListsFromTheTop() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("status-\(UUID().uuidString)")
        let src = dir.appendingPathComponent("src/lib")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "hello".write(to: src.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("bundle.zip")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        task.arguments = ["-q", "-r", zip.path, "."]
        task.currentDirectoryURL = dir.appendingPathComponent("src")
        try task.run(); task.waitUntilExit()

        let own = laidOut(ZipArchiveView())
        XCTAssertTrue(own.statusLineShownForTesting, "with no host the view keeps its own line")
        XCTAssertGreaterThan(own.listTopGapForTesting, 10)

        let view = laidOut(ZipArchiveView())
        var said: [String] = []
        view.onStatus = { said.append($0) }
        view.load(url: zip)
        let started = Date()
        while !(said.last ?? "").contains("files"), Date().timeIntervalSince(started) < 5 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(said.contains { $0.contains("Reading") }, "\(said)")
        XCTAssertTrue(said.last?.hasPrefix("Zip · 1 file") == true, "\(said)")
        XCTAssertFalse(view.statusLineShownForTesting)
        XCTAssertEqual(view.listTopGapForTesting, 0, accuracy: 0.5, "the list starts at the top")
    }

    func testRecordsSayTheirSummaryToTheHost() {
        let view = laidOut(RecordTableView())
        var said: [String] = []
        view.onStatus = { said.append($0) }
        view.load(RecordTable(columns: [], rows: [], summary: "3 entries · 1 disabled", empty: ("tablecells", "", "")))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(said.last, "3 entries · 1 disabled")
        XCTAssertFalse(view.summaryShownForTesting)
        XCTAssertEqual(view.tableTopGapForTesting, 0, accuracy: 0.5)
    }

    /// The .env row stays while its Reveal switch has values to reveal, and goes when it has none.
    func testAnEnvFileKeepsItsRowOnlyForTheRevealSwitch() {
        let view = laidOut(EnvTableView())
        var said: [String] = []
        view.onStatus = { said.append($0) }
        view.load("API_KEY=sk-live-abcdef0123456789\nPORT=3000\n")
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(said.last?.hasPrefix("2 variables"), true, "\(said)")
        XCTAssertFalse(view.summaryShownForTesting)
        XCTAssertGreaterThan(view.tableTopGapForTesting, 10, "the Reveal switch keeps its row")
        view.load("PORT=3000\nHOST=localhost\n")
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(said.last, "2 variables")
        XCTAssertEqual(view.tableTopGapForTesting, 0, accuracy: 0.5, "nothing to reveal, no row")
    }
}
