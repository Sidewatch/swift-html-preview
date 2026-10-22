//
//  CrontabTableTests.swift
//  PreviewViewsTests
//
//  The crontab table: each job's schedule in words and its next runs.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import PreviewViews

final class CrontabTableTests: XCTestCase {
    private let london = TimeZone(identifier: "Europe/London")!
    private let british = Locale(identifier: "en_GB")
    /// Thursday 22 October 2026, 14:37 in London.
    private let now = ISO8601DateFormatter().date(from: "2026-10-22T13:37:00Z")!

    private func next(_ crontab: String) -> [String] {
        RecordFormat.crontabTable(crontab, now: now, timeZone: london, locale: british).rows.compactMap { $0.cells["next"] }
    }

    func testEachJobListsItsNextThreeRuns() {
        XCTAssertEqual(next("0 9 * * 1-5 /usr/local/bin/backup\n"), ["Fri 09:00 · Mon 09:00 · Tue 09:00"])
        XCTAssertEqual(next("*/20 * * * * poll\n"), ["Thu 14:40 · Thu 15:00 · Thu 15:20"])
    }

    func testRunsPastTheComingWeekNameTheDayAndBeyondThisYearTheYear() {
        // British English writes "1 Nov at 03:00"; the system's format for the locale is kept.
        XCTAssertEqual(next("0 3 1 * * monthly\n"), ["1 Nov at 03:00 · 1 Dec at 03:00 · 1 Jan 2027 at 03:00"])
        // CronSchedule looks eight years ahead: two leap days.
        XCTAssertEqual(next("0 0 29 2 * leap\n"), ["29 Feb 2028 at 00:00 · 29 Feb 2032 at 00:00"])
    }

    func testStartupNeverAndInvalidSchedulesSaySo() {
        XCTAssertEqual(next("@reboot start\n0 0 30 2 * never\n"), ["At startup", "Never"])
    }

    func testAJobsZoneIsShownWhenItIsNotThisMacs() {
        // Tokyo is 8 hours ahead of London in October: 09:00 there is the next morning's 09:00.
        XCTAssertEqual(next("CRON_TZ=Asia/Tokyo\n0 9 * * * report\n"), ["Fri 09:00 · Sat 09:00 · Sun 09:00 GMT+9"])
    }

    func testTheNextColumnSitsAfterTheWords() {
        let table = RecordFormat.crontabTable("0 9 * * * job\n", now: now, timeZone: london, locale: british)
        XCTAssertEqual(table.columns.map(\.id), ["schedule", "when", "next", "command", "tags"])
    }
}
