//
//  RecordFormat.swift
//  Sidewatch
//
//  The line-oriented files the record table shows — hosts, crontab, Procfile, ssh config,
//  gettext catalogs — and how a file is recognised as one.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import CodeLanguage
import FoundationExtensions

/// A file the `RecordTableView` shows as rows: each line (or block, or message) a record, its
/// parts in columns, edited in place. The readers and line edits are swift-data-converter's;
/// this is the join.
public nonisolated enum RecordFormat: String, CaseIterable, Sendable {
    case hosts, crontab, procfile, sshConfig, gettext

    /// The format of a document, by its language or its name; nil for anything else.
    public static func of(url: URL?, language: Language) -> RecordFormat? {
        switch language {
        case .hosts: return .hosts
        case .crontab: return .crontab
        case .gettext: return .gettext
        default: break
        }
        guard let url else { return nil }
        let name = url.lastPathComponent
        if url.lowercasedExtension == "hosts" { return .hosts }
        if name == "Procfile" || name.hasPrefix("Procfile.") { return .procfile }
        if name == "ssh_config" || name == "config" && url.deletingLastPathComponent().lastPathComponent == ".ssh" { return .sshConfig }
        return nil
    }

    /// The key a "show the table first" choice is remembered under: the language's for the formats
    /// that have one, the format's own for the two read as plain text (Procfile, ssh config).
    public var previewDefaultKey: String { "record.\(rawValue)" }
}
