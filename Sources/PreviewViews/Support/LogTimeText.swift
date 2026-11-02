//
//  LogTimeText.swift
//  PreviewViews
//
//  A log entry's time as the table writes it.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import LogReader

/// `2026-10-01 00:00:00.021`: a time the line gave a zone for in this Mac's zone, one written without a zone as it
/// was written (the reader took it as UTC).
enum LogTimeText {
    static func text(_ instant: LogInstant) -> String {
        (instant.zoned ? local : asWritten).string(from: Date(timeIntervalSince1970: instant.seconds))
    }

    private static let local = formatter(TimeZone.current)
    private static let asWritten = formatter(TimeZone(identifier: "UTC")!)

    private static func formatter(_ zone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }
}
