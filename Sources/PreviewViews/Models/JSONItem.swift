//
//  JSONItem.swift
//  Sidewatch
//
//  One node of a parsed document — JSON, YAML, TOML, XML, a plist, INI, .properties, .strings — for the collapsible tree preview.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import DataConverter

/// One node of a parsed document, for the collapsible tree preview.
public final class JSONItem {
    public let label: String  // key, or "[index]"
    public let valueText: String  // leaf value ("string" in quotes, number, bool, null)
    public let typeLabel: String  // right-aligned type badge: object / array [n] / string / number / …
    public let glyph: String  // type icon
    public let kind: Kind
    public let children: [JSONItem]
    public let path: String  // JSONPath to this node, e.g. $.users[0].name
    /// The same path as steps, for the editors (`JSONEdit.site`, `YAMLStructure.site`…).
    public let components: [StructuredEdit.PathComponent]
    /// A string value as the file holds it (the shown text collapses its line breaks).
    public let rawString: String?
    /// Whether the format lets this key be renamed on its own (`TreeFormat.renamesKey`).
    public let renamable: Bool

    public init(
        label: String, valueText: String, typeLabel: String, glyph: String, kind: Kind, children: [JSONItem],
        path: String, components: [StructuredEdit.PathComponent], rawString: String?, renamable: Bool
    ) {
        self.label = label
        self.valueText = valueText
        self.typeLabel = typeLabel
        self.glyph = glyph
        self.kind = kind
        self.children = children
        self.path = path
        self.components = components
        self.rawString = rawString
        self.renamable = renamable
    }
}
