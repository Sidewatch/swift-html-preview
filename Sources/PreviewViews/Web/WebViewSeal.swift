//
//  WebViewSeal.swift
//  PreviewViews
//
//  The seal an offline web view wears: no network, no persistence, local navigation only.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import WebKit

/// The three seals of a web view that shows a local page and must not phone home — a README's
/// preview, an agent-written HTML file: a non-persistent data store, a compiled content rule
/// list that blocks every network-scheme resource load (the only thing that stops subresources;
/// `file:`, `data:`, `about:` and `blob:` pass), and a navigation rule that lets only those local
/// schemes through as a top frame. The page's own inline script may still run when the host
/// allows it: fetch and WebSocket fall under the rule list, and a `location = "https://…"` is a
/// navigation the rule cancels. One implementation, shared by an app and its Quick Look extension.
public enum WebViewSeal {
    /// The schemes a top-frame navigation may use.
    public static let localSchemes: Set<String> = ["file", "about", "data", "blob"]

    /// The content rules: one block rule per network scheme. WebKit's `url-filter` regex has no
    /// alternation — a single `^(https?|wss?|ftp)://` fails to compile and would leave the view
    /// unsealed — so each scheme is its own rule.
    public static let networkBlockRules =
        #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^ftp://"},"action":{"type":"block"}}]"#

    /// The rule list's name in WebKit's compiled store.
    public static let ruleListIdentifier = "SidewatchOfflineWebView"

    /// A configuration with a non-persistent data store and page JavaScript on or off.
    public static func configuration(javaScript: Bool) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = javaScript
        return configuration
    }

    /// Whether a top-frame navigation to `url` may proceed: a local scheme only.
    public static func allowsNavigation(to url: URL?) -> Bool {
        localSchemes.contains(url?.scheme?.lowercased() ?? "")
    }

    /// Compiles ``networkBlockRules`` and adds them to `webView`; `completion(true)` once the view
    /// is sealed, `completion(false)` when the rules did not compile — then nothing should load.
    public static func arm(_ webView: WKWebView, completion: @escaping @MainActor (Bool) -> Void) {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: ruleListIdentifier, encodedContentRuleList: networkBlockRules
        ) { list, error in
            MainActor.assumeIsolated {
                guard let list else {
                    NSLog("WebViewSeal: the network block did not compile (%@)", error?.localizedDescription ?? "unknown")
                    completion(false)
                    return
                }
                webView.configuration.userContentController.add(list)
                completion(true)
            }
        }
    }
}
