//
//  SQLStatementKind.swift
//  PreviewViews
//
//  What running a SQL script would do to a database: read it, write to it, or lose data.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import SQLiteReader

/// What running a SQL script would do to the database, by its statements' leading verbs: read it,
/// write to it, or destroy data — the console opens a read-write connection for the second and
/// asks before the third.
public nonisolated enum SQLStatementKind: Int, Comparable, Sendable {
    /// Returns rows and changes nothing: SELECT, VALUES, EXPLAIN, a PRAGMA that only asks.
    case read
    /// Changes the database without losing what is there: INSERT, CREATE, a PRAGMA that sets.
    case write
    /// Can lose data: DELETE, UPDATE, DROP, ALTER, REPLACE, TRUNCATE.
    case destructive

    public static func < (a: SQLStatementKind, b: SQLStatementKind) -> Bool { a.rawValue < b.rawValue }

    private static let destructiveVerbs: Set<String> = ["DELETE", "UPDATE", "DROP", "ALTER", "REPLACE", "TRUNCATE"]
    private static let readVerbs: Set<String> = ["SELECT", "VALUES", "EXPLAIN"]

    /// The strongest kind among the script's statements; an unknown verb counts as a write.
    public static func of(script: String) -> SQLStatementKind {
        SQLiteDB.statements(in: script).map(of(statement:)).max() ?? .read
    }

    /// One statement's kind by its leading verb, comments skipped. A common-table expression is
    /// judged by the verb after its definitions; a PRAGMA writes when it carries a value.
    public static func of(statement: String) -> SQLStatementKind {
        let words = leadingWords(of: statement, count: 2)
        guard let verb = words.first else { return .read }
        switch verb {
        case "WITH": return verbAfterCommonTableExpressions(statement).map(kind(ofVerb:)) ?? .write
        case "PRAGMA": return statement.contains("=") || statement.contains("(") ? .write : .read
        default: return kind(ofVerb: verb)
        }
    }

    /// The verb and object a confirmation names: "DELETE FROM users", "DROP TABLE users".
    public static func summary(of script: String) -> String {
        let statement =
            SQLiteDB.statements(in: script).first { of(statement: $0) == .destructive } ?? SQLiteDB.statements(in: script).first ?? script
        return leadingWords(of: statement, count: 3).joined(separator: " ")
    }

    private static func kind(ofVerb verb: String) -> SQLStatementKind {
        if readVerbs.contains(verb) { return .read }
        return destructiveVerbs.contains(verb) ? .destructive : .write
    }

    /// The first `count` words of the statement with comments removed, the first upper-cased.
    static func leadingWords(of statement: String, count: Int) -> [String] {
        var words = stripped(statement).split(whereSeparator: { $0.isWhitespace || $0 == "(" || $0 == ";" })
            .prefix(count).map(String.init)
        if let first = words.first { words[0] = first.uppercased() }
        return words
    }

    /// The top-level verb that follows a `WITH` clause's definitions: the first keyword at
    /// parenthesis depth zero after the leading `WITH`.
    private static func verbAfterCommonTableExpressions(_ statement: String) -> String? {
        var depth = 0
        var word = ""
        var sawWith = false
        for ch in stripped(statement) {
            if ch == "(" { depth += 1; word = ""; continue }
            if ch == ")" { depth -= 1; word = ""; continue }
            guard depth == 0 else { continue }
            if ch.isLetter {
                word.append(ch)
                continue
            }
            if !word.isEmpty { if let verb = topLevelVerb(word, sawWith: &sawWith) { return verb } }
            word = ""
        }
        return word.isEmpty ? nil : topLevelVerb(word, sawWith: &sawWith)
    }

    /// Whether `word` is the statement's verb once the leading WITH has gone by.
    private static func topLevelVerb(_ word: String, sawWith: inout Bool) -> String? {
        let upper = word.uppercased()
        if !sawWith { sawWith = upper == "WITH"; return nil }
        return ["SELECT", "INSERT", "UPDATE", "DELETE", "REPLACE", "VALUES"].contains(upper) ? upper : nil
    }

    /// The statement without `--` and `/* */` comments, strings left as they are.
    static func stripped(_ statement: String) -> String {
        var out = ""
        var chars = statement[...]
        var quote: Character?
        while let ch = chars.first {
            chars.removeFirst()
            if let q = quote {
                out.append(ch)
                if ch == q { quote = nil }
                continue
            }
            if ch == "'" || ch == "\"" { quote = ch; out.append(ch); continue }
            if ch == "-", chars.first == "-" {
                if let end = chars.firstIndex(of: "\n") { chars = chars[end...] } else { chars = chars[chars.endIndex...] }
                out.append(" ")
                continue
            }
            if ch == "/", chars.first == "*" {
                if let end = chars.range(of: "*/") { chars = chars[end.upperBound...] } else { chars = chars[chars.endIndex...] }
                out.append(" ")
                continue
            }
            out.append(ch)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
