//
//  TreeFormat+Reading.swift
//  Sidewatch
//
//  Reading a structured document into the tree's value, and which keys it can rename.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import CodeHighlighting
import DataConverter

extension TreeFormat {
    /// The document's structure; `bytes` is read for a binary property list, which has no
    /// text (the document under it is empty and read-only). JSON is not read here — the tree
    /// keeps its own `JSONSerialization` path with sorted keys.
    public func value(of text: String, bytes: () -> Data?) -> StructuredValue? {
        switch self {
        case .json: return nil
        // One JSON document per LINE: a whole-file JSON reader sees a syntax error on line two
        // and gives up, so agent transcripts need this reader to show as a tree.
        case .jsonLines: return JSONLines.value(of: text)
        case .yaml: return YAMLStructure.stream(of: text)
        case .toml: return TOMLStructure.value(of: text)
        case .xml: return XMLStructure.value(of: text)
        case .plist:
            if text.isEmpty || text.hasPrefix("bplist"), let data = bytes() { return PlistStructure.value(of: data) }
            return PlistStructure.value(of: text)
        case .ini: return INIStructure.value(of: text)
        case .properties: return PropertiesStructure.value(of: text)
        case .strings:
            if text.isEmpty || text.hasPrefix("bplist"), let data = bytes() { return PlistStructure.value(of: data) }
            return StringsStructure.value(of: text)
        }
    }

    /// Whether the key named `label` can be renamed in place: an XML element's name is written
    /// twice (only its `@attributes` rename), and `#text` is not a key at all.
    public func renamesKey(_ label: String) -> Bool {
        self == .xml ? label.hasPrefix("@") : true
    }
}
