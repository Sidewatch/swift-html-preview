//
//  LocalImageInlinerTests.swift
//  PreviewHTMLTests
//
//  Local images become data URIs; the src is read as a browser reads it.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import PreviewHTML

/// `LocalImageInliner`.
final class LocalImageInlinerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("inline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("shots"), withIntermediateDirectories: true)
        for name in ["shots/my shot.png", "a&b.png", "plain.png"] { try Data("PNG!".utf8).write(to: dir.appendingPathComponent(name)) }
        try Data(repeating: 7, count: 64).write(to: dir.appendingPathComponent("big.png"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func inlined(_ src: String, cap: Int = LocalImageInliner.byteCap) -> String {
        LocalImageInliner.inline("<p><img src=\"\(src)\" alt=\"x\"></p>", baseURL: dir, byteCap: cap)
    }

    private let png = "data:image/png;base64,\(Data("PNG!".utf8).base64EncodedString())"

    func testASourceIsReadAsABrowserReadsIt() {
        XCTAssertEqual(inlined("plain.png"), "<p><img src=\"\(png)\" alt=\"x\"></p>")
        XCTAssertTrue(inlined("shots/my%20shot.png").contains(png), "percent-encoding decoded")
        XCTAssertTrue(inlined("a&amp;b.png").contains(png), "the attribute's escape undone")
        XCTAssertTrue(inlined("plain.png?raw=1#top").contains(png), "query and fragment dropped")
        XCTAssertTrue(inlined(dir.appendingPathComponent("plain.png").path).contains(png), "an absolute path")
    }

    func testRemoteMissingAndOversizedImagesKeepTheirSource() {
        for src in ["https://example.com/a.png", "//cdn.example.com/a.png", "data:image/png;base64,AAAA", "missing.png"] {
            XCTAssertEqual(inlined(src), "<p><img src=\"\(src)\" alt=\"x\"></p>", src)
        }
        XCTAssertTrue(inlined("big.png", cap: 32).contains("src=\"big.png\""), "over the cap")
        XCTAssertTrue(inlined("big.png", cap: 128).contains("data:image/png"), "under it")
    }
}
