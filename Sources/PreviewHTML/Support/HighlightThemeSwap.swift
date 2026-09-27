//
//  HighlightThemeSwap.swift
//  PreviewHTML
//
//  Puts a snapshot's colours on the highlighter for one render and takes them off again.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import CodeHighlighting

/// The highlighter's colour provider is a global; a render installs the snapshot's colours and
/// restores whatever was there (a host app that renders in-process keeps its own provider).
enum HighlightThemeSwap {
    @MainActor static func install(_ theme: ThemeSnapshot?) -> any TokenColorProviding {
        let previous = HighlightTheme.colors
        if let theme { HighlightTheme.colors = SnapshotColors(theme) }
        return previous
    }
    @MainActor static func restore(_ previous: any TokenColorProviding) { HighlightTheme.colors = previous }
}
