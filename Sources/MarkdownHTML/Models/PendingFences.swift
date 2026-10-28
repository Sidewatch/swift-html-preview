//
//  PendingFences.swift
//  MarkdownHTML
//
//  A rendered page whose code blocks are still to be coloured.
//
//  Created by David Sherlock on 10/28/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// A Markdown page rendered with its code blocks still to colour
/// (``MarkdownHTML/renderPendingFences(_:highlights:math:diagramFences:)``): the page is built wherever building it
/// is cheap to wait for, each fence is coloured wherever its highlighter has to run, and ``filled(with:)`` puts the
/// two together.
public struct PendingFences: Equatable, Sendable {
    /// The page, each fence to colour standing as a placeholder.
    public let html: String
    /// The fences to colour, in the order they stand on the page.
    public let fences: [PendingFence]
    /// The character around each placeholder's number: one the document itself never uses.
    let mark: Unicode.Scalar
}
