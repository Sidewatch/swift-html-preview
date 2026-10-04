//
//  TreeFormat+Detection.swift
//  Sidewatch
//
//  Which structured format a file is, by its name or its language.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import CodeLanguage
import FoundationExtensions

extension TreeFormat {
    /// The format of a document, by its extension first (`.plist` is XML with a plist's shape,
    /// `.cfg` is INI) and by its detected language otherwise (`Cargo.lock` is TOML,
    /// `.gitconfig` and `.editorconfig` are INI, `Package.resolved` is JSON). Nil for anything
    /// the tree cannot show. SVG is an image here, never a tree.
    public static func of(url: URL?, language: Language) -> TreeFormat? {
        if let url {
            if isExcluded(url) { return nil }
            switch url.lowercasedExtension {
            case "json", "jsonc", "json5": return .json
            case "jsonl", "ndjson": return .jsonLines
            case "yaml", "yml": return .yaml
            case "toml": return .toml
            case "plist", "entitlements", "stringsdict": return .plist  // a .stringsdict is an XML plist, whatever its language
            case "ini", "cfg", "cnf", "desktop", "service", "socket", "timer", "reg": return .ini
            case "properties": return .properties
            case "strings": return .strings
            case "xml", "xsd", "xsl", "xslt", "xaml", "csproj", "vbproj", "fsproj", "props", "targets", "storyboard", "xib", "nuspec",
                "wsdl", "rss", "atom", "opml", "gpx", "kml":
                return .xml
            default: break
            }
        }
        switch language {
        case .json, .jsonc, .json5: return .json  // `tsconfig.json`, `devcontainer.json`, `bun.lock`
        case .jsonlines: return .jsonLines
        case .yaml: return .yaml
        case .toml: return .toml
        case .xml, .xslt: return .xml
        case .plist: return .plist
        case .ini, .gitconfig, .editorconfig, .systemd: return .ini  // a systemd unit is [Section] key=value
        case .properties: return .properties
        case .strings: return .strings
        default: return nil
        }
    }

    /// Whether a JSON document of `language` may carry comments, trailing commas and JSON5's bare
    /// keys: JSONC and JSON5 are read leniently, while plain JSON stays strict, so a stray comma in a
    /// `.json` still says "Invalid JSON".
    public static func readsLeniently(_ language: Language) -> Bool { language == .jsonc || language == .json5 }

    /// The value of a JSON document, or nil when it does not parse; `lenient` reads JSONC and JSON5.
    public static func jsonObject(_ text: String, lenient: Bool) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: lenient ? [.fragmentsAllowed, .json5Allowed] : [.fragmentsAllowed])
    }

    /// Files whose LANGUAGE is a tree format but whose shape is not one document the reader can
    /// show: an SVG is an image; a `.ips` crash report is two JSON documents; a yarn v1
    /// `yarn.lock` only looks like YAML. These open on their source, with no tree offered.
    public static let excludedExtensions: Set<String> = ["svg", "ips"]
    /// Excluded file names, matched lowercased.
    public static let excludedNames: Set<String> = ["yarn.lock"]
    /// Whether `url` is one of the files above, never offered a tree.
    public static func isExcluded(_ url: URL) -> Bool {
        excludedExtensions.contains(url.lowercasedExtension) || excludedNames.contains(url.lastPathComponent.lowercased())
    }

    /// Every extension `of(url:language:)` answers from, for the preview gate.
    public static let extensions: Set<String> = [
        "json", "jsonc", "json5", "jsonl", "ndjson", "yaml", "yml", "toml", "plist", "entitlements", "stringsdict", "ini", "cfg", "cnf",
        "desktop", "service",
        "socket", "timer", "reg", "properties", "strings",
        "xml", "xsd", "xsl", "xslt", "xaml", "csproj", "vbproj", "fsproj", "props", "targets", "storyboard", "xib", "nuspec", "wsdl", "rss",
        "atom", "opml", "gpx", "kml",
    ]
    /// Every language it answers from.
    public static let languages: Set<Language> = [
        .json, .jsonc, .json5, .jsonlines, .yaml, .toml, .xml, .xslt, .plist, .ini, .gitconfig, .editorconfig, .systemd, .properties,
        .strings,
    ]
}
