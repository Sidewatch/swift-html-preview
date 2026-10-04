//
//  QueryTextView.swift
//  Sidewatch
//
//  A NSTextView that fires `onRun` on ⌘↩ so you can run a query from the editor.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import UniformTypeIdentifiers
import AppKitViews

/// A NSTextView that fires `onRun` on ⌘↩ so you can run a query from the editor.
public final class QueryTextView: NSTextView {
    /// SQL, not prose: no smart quotes, no autocorrect. On attach, so `init()` stays inherited.
    public override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); disableSystemTextIntelligence() }
    /// ⌘↩: run the query in the box.
    public var onRun: (() -> Void)?
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.command) { onRun?(); return }
        super.keyDown(with: event)
    }
}
