//
//  TreeFormat+Editing.swift
//  Sidewatch
//
//  The one text edit a key or value typed into the tree means, per format.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import CodeHighlighting
import DataConverter

extension TreeFormat {
    /// The one edit a typed key or value of `item` means — the range to replace and what to
    /// write there, the kind kept — or nil when the format has nowhere to write it (a binary
    /// plist, an XML element's name).
    public func replacement(in text: String, item: JSONItem, target: JSONTreeView.EditTarget, typed: String) -> (
        range: NSRange, replacement: String
    )? {
        let key = target == .key
        let kind = item.scalarKind ?? .string
        let value = item.editedValue(typed)
        switch self {
        case .json:
            guard let site = JSONEdit.site(in: text, path: item.components), let range = key ? site.key : site.value else { return nil }
            return (NSRange(range, in: text), key ? JSONEdit.encodedKey(typed) : JSONEdit.encodedValue(value, kind: kind))
        case .jsonLines:
            // The path's first step names the RECORD; everything after it is a path inside that
            // one line's document. So the finder runs on the line alone and its answer is
            // shifted by where the line starts — an edit can only ever touch its own record.
            guard case .index(let record)? = item.components.first,
                let line = JSONLines.records(in: text).first(where: { $0.index == record })
            else { return nil }
            let rest = Array(item.components.dropFirst())
            // An empty rest means the record ROW itself, which is only editable when the record
            // did not parse and is standing in as its own text. We do not know its shape, so we
            // do not rewrite it.
            guard !rest.isEmpty else { return nil }
            let lineText = (text as NSString).substring(with: line.range)
            guard let site = JSONEdit.site(in: lineText, path: rest), let range = key ? site.key : site.value else { return nil }
            let within = NSRange(range, in: lineText)
            return (
                NSRange(location: line.range.location + within.location, length: within.length),
                key ? JSONEdit.encodedKey(typed) : JSONEdit.encodedValue(value, kind: kind)
            )
        case .yaml:
            guard let site = YAMLStructure.site(in: text, path: item.components), let range = key ? site.key : site.value else {
                return nil
            }
            return (range, key ? YAMLEdit.encodedKey(typed) : YAMLEdit.encodedScalar(value, kind: kind))
        case .toml:
            guard let site = TOMLStructure.site(in: text, path: item.components), let range = key ? site.key : site.value else {
                return nil
            }
            return (range, key ? TOMLEdit.encodedKey(typed) : TOMLEdit.encodedScalar(value, kind: kind))
        case .xml:
            guard let site = XMLStructure.site(in: text, path: item.components), let range = key ? site.key : site.value else { return nil }
            if key { return (range, XMLEdit.encodedAttributeName(typed)) }
            return (range, item.label.hasPrefix("@") ? XMLEdit.encodedAttribute(value) : XMLEdit.encodedText(value))
        case .plist:
            guard let site = PlistStructure.site(in: text, path: item.components), let range = key ? site.key : site.value else {
                return nil
            }
            return (range, key ? PlistEdit.encodedKey(typed) : PlistEdit.encodedScalar(value, kind: kind))
        case .ini: return INIStructure.replacement(in: text, path: item.components, key: key, with: key ? typed : value)
        case .properties: return PropertiesStructure.replacement(in: text, path: item.components, key: key, with: key ? typed : value)
        case .strings:
            guard !text.hasPrefix("bplist") else { return nil }
            return StringsStructure.replacement(in: text, path: item.components, key: key, with: key ? typed : value)
        }
    }
}
