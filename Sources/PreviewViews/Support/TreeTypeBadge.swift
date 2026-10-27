//
//  TreeTypeBadge.swift
//  PreviewViews
//
//  The structure tree's type badges, each looked up once.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The type badge beside each value in the structure tree, localized once. A lookup per node was most of the tree's
/// main-thread cost: `String(localized:)` reads the bundle's tables and parses the string on every call, and a 2 MB
/// JSON file has 120,000 nodes (a 473 ms stall, 27 Oct 2026). The counted badges ("array [2]") are kept per count.
nonisolated enum TreeTypeBadge {
    static let object = String(localized: "object", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value")
    static let mapping = String(localized: "mapping", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value")
    static let string = String(localized: "string", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value")
    static let number = String(localized: "number", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value")
    static let boolean = String(localized: "boolean", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value")

    /// "array [n]" for a JSON array of `count` items.
    static func array(_ count: Int) -> String {
        arrays.badge(for: count) {
            String(localized: "array [\($0)]", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value")
        }
    }

    /// "sequence [n]" for a structured document's sequence of `count` items.
    static func sequence(_ count: Int) -> String {
        sequences.badge(for: count) {
            String(localized: "sequence [\($0)]", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value")
        }
    }

    private static let arrays = CountedBadges()
    private static let sequences = CountedBadges()
}

/// A badge per count, each made once. Locked: nothing requires a tree to be built on the main thread.
nonisolated private final class CountedBadges: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [Int: String] = [:]

    func badge(for count: Int, make: (Int) -> String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let badge = made[count] { return badge }
        let badge = make(count)
        made[count] = badge
        return badge
    }
}
