//
//  RecordFormat+Table.swift
//  Sidewatch
//
//  Each record format's text as a `RecordTable`: its columns, rows and the line edits behind
//  each editable cell and enable switch.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import DataConverter

nonisolated extension RecordFormat {
    /// `text` as a table. Nonisolated: a long file's table is built off the main thread.
    public func table(_ text: String) -> RecordTable {
        switch self {
        case .hosts: return Self.hostsTable(text)
        case .crontab: return Self.crontabTable(text)
        case .procfile: return Self.procfileTable(text)
        case .sshConfig: return Self.sshTable(text)
        case .gettext: return Self.gettextTable(text)
        }
    }

    // MARK: - hosts

    public static func hostsTable(_ text: String) -> RecordTable {
        let entries = HostsFile.parse(text)
        // Looked up once: a localised lookup per row cost more than the parse on a long file.
        let blockedTag = String(
            localized: "blocked", bundle: .module, comment: "hosts table tag: the entry points its names nowhere (0.0.0.0)")
        var rows: [RecordTable.Row] = []
        var section: String?
        for entry in entries {
            if entry.section != section, let title = entry.section {
                rows.append(RecordTable.Row(cells: [:], line: entry.line, section: title))
            }
            section = entry.section
            var tags: [String] = []
            if entry.isBlocked {
                tags.append(blockedTag)
            }
            if entry.isIPv6 { tags.append("IPv6") }
            let line = entry.line
            rows.append(
                RecordTable.Row(
                    cells: [
                        "address": entry.address, "names": entry.names.joined(separator: " "), "comment": entry.comment ?? "",
                        "tags": tags.joined(separator: " "),
                    ],
                    line: line, enabled: entry.isEnabled,
                    edits: [
                        "address": { HostsFile.replacingAddress(in: $0, line: line, with: $1) },
                        "names": { HostsFile.replacingNames(in: $0, line: line, with: [$1]) },
                        "comment": { HostsFile.replacingComment(in: $0, line: line, with: $1) },
                    ],
                    toggle: { HostsFile.settingEnabled(in: $0, line: line, $1) }))
        }
        let disabled = entries.filter { !$0.isEnabled }.count
        return RecordTable(
            columns: [
                .init(
                    id: "address", title: String(localized: "Address", bundle: .module, comment: "hosts table column"), width: 190,
                    style: .key),
                .init(
                    id: "names", title: String(localized: "Host Names", bundle: .module, comment: "hosts table column"), width: 360,
                    style: .chips),
                .init(id: "tags", title: "", width: 110, style: .tags),
                .init(
                    id: "comment",
                    title: String(localized: "Comment", bundle: .module, comment: "record table column: a line's trailing comment"),
                    width: 240, style: .prose),
            ],
            rows: rows,
            summary: disabled > 0
                ? String(localized: "\(entries.count) entries · \(disabled) disabled", bundle: .module, comment: "hosts table summary")
                : String(localized: "\(entries.count) entries", bundle: .module, comment: "hosts table summary"),
            empty: (
                "network", String(localized: "No Entries", bundle: .module, comment: "hosts table empty state"),
                String(localized: "This file has no address lines.", bundle: .module)
            ))
    }

    // MARK: - crontab

    public static func crontabTable(_ text: String) -> RecordTable {
        let file = Crontab.parse(text)
        var rows: [RecordTable.Row] = []
        if !file.assignments.isEmpty {
            rows.append(
                RecordTable.Row(
                    cells: [:], line: file.assignments[0].line,
                    section: String(localized: "Environment", bundle: .module, comment: "crontab table section: NAME=value lines")))
            for a in file.assignments {
                let line = a.line
                rows.append(
                    RecordTable.Row(
                        cells: ["schedule": a.key, "command": a.value], line: line,
                        edits: ["command": { Crontab.replacingValue(in: $0, line: line, with: $1) }]))
            }
        }
        if !file.jobs.isEmpty, !file.assignments.isEmpty {
            rows.append(
                RecordTable.Row(
                    cells: [:], line: file.jobs[0].line,
                    section: String(localized: "Jobs", bundle: .module, comment: "crontab table section: the scheduled jobs")))
        }
        let notLoggedTag = String(localized: "not logged", bundle: .module, comment: "crontab table tag: a '-' job is not logged to syslog")
        // One description per distinct schedule: a long crontab repeats them.
        var described: [String: CronSchedule.Description?] = [:]
        for job in file.jobs {
            let line = job.line
            let description: CronSchedule.Description?
            if let cached = described[job.schedule] {
                description = cached
            } else {
                description = CronSchedule.describe(job.schedule)
                described[job.schedule] = description
            }
            rows.append(
                RecordTable.Row(
                    cells: [
                        "schedule": job.schedule, "when": description?.text ?? "",
                        "command": job.command,
                        "tags": job.isQuiet ? notLoggedTag : "",
                    ],
                    line: line, enabled: job.isEnabled, warning: description?.warning,
                    edits: [
                        "schedule": { Crontab.replacingSchedule(in: $0, line: line, with: $1) },
                        "command": { Crontab.replacingCommand(in: $0, line: line, with: $1) },
                    ],
                    toggle: { Crontab.settingEnabled(in: $0, line: line, $1) }))
        }
        let disabled = file.jobs.filter { !$0.isEnabled }.count
        return RecordTable(
            columns: [
                .init(
                    id: "schedule",
                    title: String(localized: "Schedule", bundle: .module, comment: "crontab table column: the five cron fields"),
                    width: 150,
                    style: .key),
                .init(
                    id: "when", title: String(localized: "When", bundle: .module, comment: "crontab table column: the schedule in words"),
                    width: 280,
                    style: .prose),
                .init(
                    id: "command",
                    title: String(localized: "Command", bundle: .module, comment: "record table column: the command a line runs"),
                    width: 420,
                    style: .code),
                .init(id: "tags", title: "", width: 90, style: .tags),
            ],
            rows: rows,
            summary: disabled > 0
                ? String(localized: "\(file.jobs.count) jobs · \(disabled) disabled", bundle: .module, comment: "crontab table summary")
                : String(localized: "\(file.jobs.count) jobs", bundle: .module, comment: "crontab table summary"),
            empty: (
                "clock", String(localized: "No Jobs", bundle: .module, comment: "crontab table empty state"),
                String(localized: "This file has no scheduled jobs.", bundle: .module)
            ))
    }

    // MARK: - Procfile

    public static func procfileTable(_ text: String) -> RecordTable {
        let entries = Procfile.parse(text)
        let rows = entries.map { e in
            let line = e.line
            return RecordTable.Row(
                cells: ["process": e.process, "command": e.command], line: line,
                edits: [
                    "process": { Procfile.replacingProcess(in: $0, line: line, with: $1) },
                    "command": { Procfile.replacingCommand(in: $0, line: line, with: $1) },
                ])
        }
        return RecordTable(
            columns: [
                .init(
                    id: "process", title: String(localized: "Process", bundle: .module, comment: "Procfile table column: the process type"),
                    width: 160,
                    style: .key),
                .init(
                    id: "command",
                    title: String(localized: "Command", bundle: .module, comment: "record table column: the command a line runs"),
                    width: 600,
                    style: .code),
            ],
            rows: rows,
            summary: String(localized: "\(entries.count) processes", bundle: .module, comment: "Procfile table summary"),
            empty: (
                "terminal", String(localized: "No Processes", bundle: .module, comment: "Procfile table empty state"),
                String(localized: "This file has no name: command lines.", bundle: .module)
            ))
    }

    // MARK: - ssh config

    public static func sshTable(_ text: String) -> RecordTable {
        let blocks = SSHConfig.parse(text)
        let shown = ["HostName", "User", "Port", "IdentityFile", "ProxyJump"]
        let rows = blocks.map { b -> RecordTable.Row in
            var cells: [String: String] = [
                "host": b.kind.isEmpty
                    ? String(localized: "(every host)", bundle: .module, comment: "ssh config table: options before the first Host block")
                    : b.kind.lowercased() == "match" ? "Match \(b.patterns)" : b.patterns
            ]
            var edits: [String: @Sendable (String, String) -> String] = [:]
            // Every shown column is editable: a value the block has is replaced (cleared, its line goes);
            // one it lacks is added under the block's last option.
            for key in shown {
                if let option = b.option(key) {
                    cells[key] = option.value
                    let line = option.line
                    edits[key] = { text, value in
                        value.trimmingCharacters(in: .whitespaces).isEmpty
                            ? SSHConfig.removingOption(in: text, line: line)
                            : SSHConfig.replacingValue(in: text, line: line, with: value)
                    }
                } else if b.line > 0 || !b.options.isEmpty {
                    let block = b
                    edits[key] = { SSHConfig.addingOption(in: $0, to: block, keyword: key, value: $1) }
                }
            }
            if b.line > 0, b.kind.lowercased() == "host" {
                let line = b.line
                edits["host"] = { SSHConfig.replacingValue(in: $0, line: line, with: $1) }
            }
            let others = b.options.filter { o in !shown.contains { $0.caseInsensitiveCompare(o.keyword) == .orderedSame } }
            cells["other"] = others.map { "\($0.keyword) \($0.value)" }.joined(separator: " · ")
            return RecordTable.Row(cells: cells, line: max(1, b.line == 0 ? (b.options.first?.line ?? 1) : b.line), edits: edits)
        }
        let hosts = blocks.filter { !$0.kind.isEmpty }.count
        return RecordTable(
            columns: [
                .init(
                    id: "host", title: String(localized: "Host", bundle: .module, comment: "ssh config table column: the Host patterns"),
                    width: 170,
                    style: .key),
                .init(id: "HostName", title: "HostName", width: 190, style: .value),
                .init(id: "User", title: "User", width: 100, style: .value),
                .init(id: "Port", title: "Port", width: 60, style: .value),
                .init(id: "IdentityFile", title: "IdentityFile", width: 180, style: .value),
                .init(id: "ProxyJump", title: "ProxyJump", width: 110, style: .value),
                .init(
                    id: "other",
                    title: String(
                        localized: "Other Options", bundle: .module, comment: "ssh config table column: every other option in the block"),
                    width: 300, style: .code),
            ],
            rows: rows,
            summary: String(localized: "\(hosts) hosts", bundle: .module, comment: "ssh config table summary"),
            empty: (
                "server.rack", String(localized: "No Hosts", bundle: .module, comment: "ssh config table empty state"),
                String(localized: "This file has no Host blocks.", bundle: .module)
            ))
    }

    // MARK: - gettext

    public static func gettextTable(_ text: String) -> RecordTable {
        let messages = GettextCatalog.parse(text).filter { !$0.isHeader }
        let fuzzyTag = String(localized: "fuzzy", bundle: .module, comment: "gettext table tag: marked for review")
        let untranslatedTag = String(localized: "untranslated", bundle: .module, comment: "gettext table tag: no translation yet")
        let pluralTag = String(localized: "plural", bundle: .module, comment: "gettext table tag: a message with plural forms")
        let rows = messages.map { m -> RecordTable.Row in
            var tags: [String] = []
            if m.isFuzzy { tags.append(fuzzyTag) }
            if m.isUntranslated { tags.append(untranslatedTag) }
            if m.plural != nil { tags.append(pluralTag) }
            let source = m.plural.map { "\(m.source) / \($0)" } ?? m.source
            var edits: [String: @Sendable (String, String) -> String] = [:]
            if m.plural == nil { edits["translation"] = { GettextCatalog.replacingTranslation(in: $0, message: m, with: $1) } }
            return RecordTable.Row(
                cells: [
                    "source": source, "translation": m.translations.joined(separator: " / "), "context": m.context ?? "",
                    "tags": tags.joined(separator: " "),
                ],
                line: m.line, edits: edits)
        }
        let untranslated = messages.filter(\.isUntranslated).count
        let fuzzy = messages.filter(\.isFuzzy).count
        return RecordTable(
            columns: [
                .init(
                    id: "source", title: String(localized: "Source", bundle: .module, comment: "gettext table column: the original text"),
                    width: 320,
                    style: .prose),
                .init(
                    id: "translation",
                    title: String(localized: "Translation", bundle: .module, comment: "gettext table column: the translated text"),
                    width: 320, style: .value),
                .init(
                    id: "context", title: String(localized: "Context", bundle: .module, comment: "gettext table column: msgctxt"),
                    width: 110, style: .prose),
                .init(id: "tags", title: "", width: 170, style: .tags),
            ],
            rows: rows,
            summary: String(
                localized: "\(messages.count) messages · \(untranslated) untranslated · \(fuzzy) fuzzy", bundle: .module,
                comment: "gettext table summary"),
            empty: (
                "character.book.closed", String(localized: "No Messages", bundle: .module, comment: "gettext table empty state"),
                String(localized: "This catalog has no messages.", bundle: .module)
            ))
    }
}
