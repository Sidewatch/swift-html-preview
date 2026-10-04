//
//  TreeFormat+Name.swift
//  Sidewatch
//
//  The name a structured format goes by.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

extension TreeFormat {
    /// The name the empty state uses ("Empty TOML").
    public var name: String {
        switch self {
        case .json: return "JSON"
        case .jsonLines: return "JSON Lines"
        case .yaml: return "YAML"
        case .toml: return "TOML"
        case .xml: return "XML"
        case .plist: return String(localized: "Property List", bundle: .module, comment: "File format name")
        case .ini: return "INI"
        case .properties: return String(localized: "Properties", bundle: .module, comment: "File format name: a Java .properties file")
        case .strings: return String(localized: "Strings", bundle: .module, comment: "File format name: an Apple .strings file")
        }
    }
}
