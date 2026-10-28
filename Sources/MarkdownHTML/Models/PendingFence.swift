//
//  PendingFence.swift
//  MarkdownHTML
//
//  One fenced code block waiting for its colours.
//
//  Created by David Sherlock on 10/28/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// One fenced code block waiting for its colours: its source and the tag it was written with.
public struct PendingFence: Equatable, Sendable {
    /// The block's source, as the fence holds it.
    public let code: String
    /// The fence's tag as written: `swift` for a block opened with ```` ```swift ````.
    public let tag: String
}
