//
//  String+JSONPath.swift
//  Sidewatch
//
//  Building a JSONPath one step at a time.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

nonisolated extension String {
    /// This JSONPath extended by the member `key`, in bracket notation when the key is not a
    /// simple identifier (so `{"a.b": …}` gives `$["a.b"]`, never the ambiguous `$.a.b`).
    public func jsonPathAppending(key: String) -> String {
        let isSimple =
            !key.isEmpty
            && !(key.first?.isNumber ?? false)
            && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        if isSimple { return "\(self).\(key)" }
        let escaped = key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\(self)[\"\(escaped)\"]"
    }
}
