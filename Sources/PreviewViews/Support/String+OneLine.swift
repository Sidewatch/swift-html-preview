//
//  String+OneLine.swift
//  Sidewatch
//
//  Text on one line, its line breaks shown as ↵.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

nonisolated extension String {
    /// The text on one line, each line break (LF, CRLF or CR) shown as ↵.
    public var oneLine: String {
        replacingOccurrences(of: "\r\n", with: "↵").replacingOccurrences(of: "\n", with: "↵").replacingOccurrences(of: "\r", with: "↵")
    }
}
