//
//  JSONItem+Parsing.swift
//  Sidewatch
//
//  Building a tree node from a decoded JSON value or a structured document's value.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import DataConverter

extension JSONItem {
    /// Recursively classifies `value` into the leaf/branch presentation fields
    /// (badge, glyph, kind, quoted text) and builds sorted-by-key child nodes.
    /// Booleans are disambiguated from numbers via `CFBooleanGetTypeID`.
    public convenience init(label: String, value: Any, path: String, components: [StructuredEdit.PathComponent] = []) {
        let children: [JSONItem], valueText: String, typeLabel: String, glyph: String, kind: Kind
        if let dict = value as? [String: Any] {
            children = dict.keys.sorted().map {
                JSONItem(label: $0, value: dict[$0] ?? NSNull(), path: path.jsonPathAppending(key: $0), components: components + [.key($0)])
            }
            valueText = "";
            typeLabel = String(localized: "object", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value");
            glyph = "{}"; kind = .container
        } else if let arr = value as? [Any] {
            children = arr.enumerated().map {
                JSONItem(
                    label: "[\($0.offset)]", value: $0.element, path: "\(path)[\($0.offset)]", components: components + [.index($0.offset)])
            }
            valueText = "";
            typeLabel = String(
                localized: "array [\(arr.count)]", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value");
            glyph = "[ ]"; kind = .container
        } else if value is NSNull {
            children = []; valueText = "null"; typeLabel = "null"; glyph = "∅"; kind = .null
        } else if let n = value as? NSNumber {
            children = []
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                valueText = n.boolValue ? "true" : "false";
                typeLabel = String(
                    localized: "boolean", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value");
                glyph = n.boolValue ? "☑" : "☐"; kind = .bool
            } else {
                valueText = "\(n)";
                typeLabel = String(
                    localized: "number", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value");
                glyph = "#";
                kind = .number
            }
        } else if let s = value as? String {
            // One line whatever the value holds: a YAML block scalar carries its newlines, and a
            // label laid out over several lines spilled across the rows beneath it.
            children = []; valueText = "\"\(s.oneLine)\"";
            typeLabel = String(localized: "string", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value");
            glyph = "\u{201C}\u{201D}"; kind = .string
        } else {
            children = []; valueText = "\(value)"; typeLabel = ""; glyph = ""; kind = .other
        }
        self.init(
            label: label, valueText: valueText, typeLabel: typeLabel, glyph: glyph, kind: kind, children: children,
            path: path, components: components, rawString: value as? String, renamable: true)
    }

    /// A structured value (YAML, TOML, XML, plists, INI, .properties and .strings): the same
    /// presentation, children in the FILE's order — a mapping's keys are not sorted, because a
    /// config file's order is the author's. `renamesKey` says which keys the format can rename
    /// in place.
    public convenience init(
        label: String, value: StructuredValue, path: String, components: [StructuredEdit.PathComponent] = [],
        renamesKey: @escaping (String) -> Bool = { _ in true }
    ) {
        let children: [JSONItem], valueText: String, typeLabel: String, glyph: String, kind: Kind
        var rawString: String?
        switch value {
        case .mapping(let pairs):
            children = pairs.map {
                JSONItem(
                    label: $0.key, value: $0.value, path: path.jsonPathAppending(key: $0.key), components: components + [.key($0.key)],
                    renamesKey: renamesKey)
            }
            valueText = "";
            typeLabel = String(localized: "mapping", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value");
            glyph = "{}"; kind = .container
        case .sequence(let items):
            children = items.enumerated().map {
                JSONItem(
                    label: "[\($0.offset)]", value: $0.element, path: "\(path)[\($0.offset)]", components: components + [.index($0.offset)],
                    renamesKey: renamesKey)
            }
            valueText = "";
            typeLabel = String(
                localized: "sequence [\(items.count)]", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value");
            glyph = "[ ]"; kind = .container
        case .string(let s):
            rawString = s
            children = []; valueText = "\"\(s.oneLine)\"";
            typeLabel = String(localized: "string", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value");
            glyph = "\u{201C}\u{201D}"; kind = .string
        case .integer(let i):
            children = []; valueText = "\(i)";
            typeLabel = String(localized: "number", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value");
            glyph = "#";
            kind = .number
        case .number(let d):
            children = []; valueText = "\(d)";
            typeLabel = String(localized: "number", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value");
            glyph = "#";
            kind = .number
        case .bool(let b):
            children = []; valueText = b ? "true" : "false";
            typeLabel = String(localized: "boolean", bundle: .module, comment: "Structure tree: the type badge beside a JSON/YAML value");
            glyph = b ? "☑" : "☐"; kind = .bool
        case .null:
            children = []; valueText = "null"; typeLabel = "null"; glyph = "∅"; kind = .null
        }
        self.init(
            label: label, valueText: valueText, typeLabel: typeLabel, glyph: glyph, kind: kind, children: children,
            path: path, components: components, rawString: rawString, renamable: renamesKey(label))
    }
}
