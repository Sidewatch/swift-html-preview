//
//  TreeFormat.swift
//  Sidewatch
//
//  The documents the structure tree shows, and how each is read and written back.
//
//  Created by David Sherlock on 9/25/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A document the `JSONTreeView` shows as ordered structure: which reader gives its value,
/// which finder and encoder rewrite one key or value in place, and which keys may be renamed.
/// This is the join the app keeps; every reader and encoder is a package's.
public enum TreeFormat: String, CaseIterable {
    case json, jsonLines, yaml, toml, xml, plist, ini, properties, strings
}
