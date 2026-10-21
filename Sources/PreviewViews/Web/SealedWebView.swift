//
//  SealedWebView.swift
//  PreviewViews
//
//  A web view that wears the seal from its first load.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import WebKit

/// A `WKWebView` under ``WebViewSeal``: non-persistent, every network load blocked, only local
/// top-frame navigations allowed. A load asked for before the rules compile is queued and runs
/// once they are in place, never unsealed; if they fail to compile the view shows nothing. Page
/// JavaScript is on by default so a page's own inline script — a filter field, a tab bar — keeps
/// working; a host that wants none passes `javaScript: false`.
open class SealedWebView: WKWebView, WKNavigationDelegate {
    private var sealed = false
    /// The latest load asked for before the seal was armed.
    private var pending: (() -> Void)?
    /// Top-frame navigations the seal cancelled, for a host's check.
    public private(set) var blockedNavigations: [URL] = []
    /// Fires when a navigation finishes.
    public var onLoadFinished: (() -> Void)?
    /// How many loads were handed to WebKit — a load queued for the seal counts when it runs.
    public private(set) var loadCount = 0

    /// A sealed view; `javaScript` is whether the page's own script runs.
    public init(frame: CGRect = .zero, javaScript: Bool = true) {
        super.init(frame: frame, configuration: WebViewSeal.configuration(javaScript: javaScript))
        navigationDelegate = self
        WebViewSeal.arm(self) { [weak self] armed in
            guard let self, armed else { return }
            self.sealed = true
            let queued = self.pending
            self.pending = nil
            if queued != nil { self.loadCount += 1 }
            queued?()
        }
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError() }

    /// Loads `html` with `baseURL` once the seal is armed.
    public func load(html: String, baseURL: URL?) {
        whenSealed { [weak self] in self?.loadHTMLString(html, baseURL: baseURL) }
    }

    /// Loads the file at `url` once the seal is armed, with read access to `access`.
    public func load(fileURL url: URL, allowingReadAccessTo access: URL) {
        whenSealed { [weak self] in self?.loadFileURL(url, allowingReadAccessTo: access) }
    }

    /// Runs `action` — a navigation — now if the seal is armed, else once it is. Only the latest
    /// queued action runs: a newer load supersedes an older one still waiting. For a subclass with
    /// loads of its own (a reload, a load that first reads the page's scroll offset).
    public func whenSealed(_ action: @escaping () -> Void) {
        if sealed {
            loadCount += 1
            action()
        } else {
            pending = action
        }
    }

    /// A navigation finished: fires ``onLoadFinished``. A subclass that overrides it calls `super`.
    open func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoadFinished?()
    }

    public func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        guard WebViewSeal.allowsNavigation(to: url) else {
            if let url { blockedNavigations.append(url) }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
