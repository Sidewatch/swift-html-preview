//
//  WebViewSealTests.swift
//  PreviewViewsTests
//
//  A sealed web view loads nothing from the network and goes nowhere but local schemes.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
import WebKit
@testable import PreviewViews

@MainActor
final class WebViewSealTests: XCTestCase {
    func testOnlyLocalSchemesMayBeNavigatedTo() {
        for allowed in ["file:///Users/me/README.md", "about:blank", "data:text/html,hi", "blob:null/abc"] {
            XCTAssertTrue(WebViewSeal.allowsNavigation(to: URL(string: allowed)), allowed)
        }
        for blocked in ["https://example.com/", "http://127.0.0.1:8080/", "ws://example.com/", "ftp://example.com/", "javascript:alert(1)"]
        {
            XCTAssertFalse(WebViewSeal.allowsNavigation(to: URL(string: blocked)), blocked)
        }
        XCTAssertFalse(WebViewSeal.allowsNavigation(to: nil))
    }

    func testTheConfigurationIsNonPersistentWithScriptAsAsked() {
        XCTAssertFalse(WebViewSeal.configuration(javaScript: true).websiteDataStore.isPersistent)
        XCTAssertTrue(WebViewSeal.configuration(javaScript: true).defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertFalse(WebViewSeal.configuration(javaScript: false).defaultWebpagePreferences.allowsContentJavaScript)
    }

    func testTheNetworkRulesCompileAndNameEveryNetworkScheme() {
        for scheme in ["^https?://", "^wss?://", "^ftp://"] {
            XCTAssertTrue(WebViewSeal.networkBlockRules.contains("\"url-filter\":\"\(scheme)\""), scheme)
        }
        let compiled = expectation(description: "the rule list compiles")
        var armed = false
        WebViewSeal.arm(WKWebView(frame: .zero, configuration: WebViewSeal.configuration(javaScript: false))) { ok in
            armed = ok
            compiled.fulfill()
        }
        wait(for: [compiled], timeout: 10)
        XCTAssertTrue(armed, "a rule list that does not compile leaves a view unsealed")
    }

    func testAPageScriptCannotNavigateTheViewToTheNetwork() {
        let web = SealedWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let loaded = expectation(description: "the page loaded")
        web.onLoadFinished = { loaded.fulfill() }
        web.load(html: "<!doctype html><html><body>hi<script>location.href='https://example.com/leak'</script></body></html>", baseURL: nil)
        wait(for: [loaded], timeout: 15)
        let deadline = Date(timeIntervalSinceNow: 3)
        while web.blockedNavigations.isEmpty, Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
        XCTAssertEqual(
            web.blockedNavigations.map(\.absoluteString), ["https://example.com/leak"], "the script ran, the navigation was cancelled")
        XCTAssertNotEqual(web.url?.host, "example.com")
    }
}
