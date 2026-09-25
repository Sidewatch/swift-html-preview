//
//  ContentSecurityPolicyTests.swift
//  PreviewHTMLTests
//
//  The page fetches nothing, whatever the file it is previewing contains.
//
//  Created by David Sherlock on 9/26/26.
//

import XCTest
@testable import PreviewHTML

/// A preview extension's page is rendered by Quick Look's web view, which the host app cannot
/// seal the way it seals its own. The policy travels with the page instead.
@MainActor
final class ContentSecurityPolicyTests: XCTestCase {
    private func page(markdown: String) -> String {
        MarkdownPreviewHTML.page(title: "notes.md", markdown: markdown, note: nil, theme: nil)
    }

    func testEveryPageCarriesThePolicy() {
        for html in [page(markdown: "# Hi"),
                     TablePreviewHTML.page(title: "d.csv", text: "a,b\n1,2\n", tabSeparated: false, theme: nil),
                     CodePreviewHTML.page(title: "a.swift", text: "let x = 1", language: .swift, theme: nil)] {
            XCTAssertTrue(html.contains("Content-Security-Policy"), "every page is sealed")
            XCTAssertTrue(html.contains("default-src 'none'"), "nothing loads unless this policy names it")
            XCTAssertTrue(html.contains("img-src data:"), "images only as data URIs — never fetched")
            XCTAssertFalse(html.contains("img-src *"), "no wildcard")
            // The policy must come before anything that could load.
            let policyAt = html.range(of: "Content-Security-Policy").map { html.distance(from: html.startIndex, to: $0.lowerBound) } ?? .max
            let styleAt = html.range(of: "<style>").map { html.distance(from: html.startIndex, to: $0.lowerBound) } ?? .max
            XCTAssertLessThan(policyAt, styleAt, "the seal is declared before the first thing it governs")
        }
    }

    /// The case that made this necessary: a tracking pixel in someone's README.
    func testARemoteImageInTheSourceCannotBeFetched() {
        let html = page(markdown: "![](https://tracker.example/pixel.png)\n\n[link](https://example.com)")
        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("img-src data:"),
                      "the URL may still be written into the markup — the policy is what stops the fetch")
        XCTAssertFalse(html.contains("img-src https:"))
        XCTAssertFalse(html.contains("connect-src"), "nothing is allowed to connect at all")
    }
}
