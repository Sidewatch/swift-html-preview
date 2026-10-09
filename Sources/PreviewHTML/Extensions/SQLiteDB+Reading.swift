//
//  SQLiteDB+Reading.swift
//  PreviewHTML
//
//  A connection for looking at a database without leaving anything beside it.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import SQLiteReader

public extension SQLiteDB {
    /// A connection for reading `url`: read-only, so browsing a WAL database leaves no `-wal` /
    /// `-shm` beside the user's file (a read-write connection creates both, and on this OS they
    /// stay after it closes).
    ///
    /// One exception, measured: a WAL database whose sidecars are ABSENT cannot be read by a
    /// read-only connection at all — SQLite answers `unable to open database file`
    /// (SQLITE_CANTOPEN) even in a writable folder, because only a read-write connection may
    /// create the shared-memory file. That case reopens read-write, which creates them; nothing
    /// else is written.
    static func openForReading(_ url: URL) -> SQLiteDB? {
        guard let db = SQLiteDB(url: url, readOnly: true) else { return nil }
        guard db.cannotBeReadReadOnly else { return db }
        return SQLiteDB(url: url, readOnly: false)
    }

    /// Whether the first read fails the way a sidecar-less WAL database does for a read-only
    /// connection.
    var cannotBeReadReadOnly: Bool {
        run("SELECT 1 FROM sqlite_master LIMIT 1").error?.contains("unable to open database file") == true
    }
}
