//
//  PreviewReading.swift
//  PreviewViews
//
//  What a preview says while a big file is read off the main thread.
//
//  Created by David Sherlock on 10/28/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// What a preview says while a big file is read off the main thread: one caption for every surface that waits.
enum PreviewReading {
    /// "Reading JSON…": the caption under the loading state's spinner, for `format`, a format's name.
    static func caption(_ format: String) -> String {
        String(
            localized: "Reading \(format)…", bundle: .module,
            comment: "A preview: a big file is being read; the placeholder is a format name such as JSON or CSV")
    }
}
