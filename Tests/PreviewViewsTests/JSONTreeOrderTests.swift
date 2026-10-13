//
//  JSONTreeOrderTests.swift
//  PreviewViewsTests
//
//  The JSON tree shows keys in the file's order — as the YAML and TOML trees do — for strict JSON
//  and for JSONC, and falls back to sorted keys only where no ordered read is possible.
//
//  Created by David Sherlock on 10/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import PreviewViews

@MainActor
final class JSONTreeOrderTests: XCTestCase {
    func testStrictJSONKeepsTheFilesOrderAtEveryLevel() {
        let tree = JSONTreeView()
        tree.load(#"{"zebra": 1, "apple": {"mango": 2, "banana": 3}, "cherry": [1, 2]}"#)
        XCTAssertEqual(tree.rootLabelsForTesting, ["zebra", "apple", "cherry"])
        XCTAssertEqual(tree.childLabelsForTesting(of: "apple"), ["mango", "banana"])
    }

    func testJSONCKeepsTheFilesOrderToo() {
        let tree = JSONTreeView()
        tree.load(
            """
            // tsconfig
            {
              "compilerOptions": { "target": "es2022", "module": "esnext", }, // trailing comma
              "include": ["src"],
            }
            """, lenient: true)
        XCTAssertEqual(tree.rootLabelsForTesting, ["compilerOptions", "include"])
        XCTAssertEqual(tree.childLabelsForTesting(of: "compilerOptions"), ["target", "module"])
    }

    func testJSON5WithUnquotedKeysStillOpensSorted() {
        let tree = JSONTreeView()
        tree.load("{zebra: 1, apple: 2}", lenient: true)
        XCTAssertEqual(tree.rootLabelsForTesting, ["apple", "zebra"], "no ordered read for JSON5 keys: Foundation's, sorted")
    }
}
