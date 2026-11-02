//
//  LogView.swift
//  PreviewViews
//
//  A log file of any size as a table of entries, filtered by level, component, time and text.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import AppKitViews
import FileTools
import LogReader
import ThemedControls

/// A log as a table: time, level, component and message for every entry, the whole selected entry (a stack trace,
/// a JSON line pretty-printed) below. The bar above filters by level (each with its count), component and time;
/// the find bar filters by text. Reading is LogReader's `LogIndex`: a background scan, so the first rows show at
/// once and the counts fill in; the rows on screen are read from the file as they are drawn. A file that grows is
/// read on, and Follow keeps the newest entry in view.
public final class LogView: NSView {
    /// Shows a line of the file in the editor (0-based): the entry's own line, from its menu.
    public var onReveal: ((_ line: Int) -> Void)?
    /// Tells the find bar how many entries hold its text once the background search lands.
    public var onMatchCount: ((_ total: Int) -> Void)?

    /// The file shown, and its index.
    public private(set) var url: URL?
    public private(set) var index: LogIndex?

    let bar = NSStackView()
    let summaryLabel = NSTextField(labelWithString: "")
    var levelBoxes: [LogLevel: ThemedCheckbox] = [:]
    let unleveledBox = ThemedCheckbox()
    let componentButton = ThemedPopUpButton(frame: .zero, pullsDown: true)
    let timeButton = ThemedPopUpButton(frame: .zero, pullsDown: true)
    let followBox = ThemedCheckbox()
    let hairline = NSView()
    let split = NSSplitView()
    let tableView = NSTableView()
    let tableScroll = ThemedScrollView()
    let detailView = NSTextView()
    let detailScroll = ThemedScrollView()
    let emptyState = EmptyStateView(symbol: "list.bullet.rectangle", title: "", subtitle: "")

    /// What the bar and the find bar ask for.
    var filter = LogFilter()
    /// The time window the menu set, relative to the last entry, or a range picked from an entry.
    var timeWindow: TimeWindow = .all
    /// The entries shown, by index; nil while the filter lets everything through (then a row is an entry).
    var visible: [Int]?
    /// Bumped by every filter run; a run that finds the number moved on is dropped.
    var filterGeneration = 0
    var filtering = false
    var refilterPending = false
    /// The last summary read, for the counts and the menus.
    var summary: LogSummary?
    /// Each shown row's first line and header, read once while it stays near the screen.
    var rowCache: [Int: (text: String, head: LogLineHead?)] = [:]

    /// How a time window is chosen.
    enum TimeWindow: Equatable {
        case all
        case last(TimeInterval)
        case range(from: Double?, to: Double?)
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError() }

    deinit {
        MainActor.assumeIsolated {
            index?.stop()
            NotificationCenter.default.removeObserver(self)
        }
    }

    // MARK: - Loading

    /// Shows the log at `url`. The file already shown is read on instead (`fileDidChange`), keeping the filters
    /// and the place: a host re-renders its preview when the file changes on disk.
    public func load(url: URL) {
        guard url != self.url || index == nil else {
            fileDidChange()
            return
        }
        index?.stop()
        self.url = url
        rowCache = [:]
        visible = nil
        summary = nil
        filter = LogFilter(text: filter.text, caseSensitive: filter.caseSensitive, isRegex: filter.isRegex)
        timeWindow = .all
        index = LogIndex(url: url)
        syncControls()
        tableView.reloadData()
        detailView.string = ""
        updateSummaryText()
        showEmptyStateIfNeeded()  // "Reading…" until the first entries land, never a blank pane
        scan()
    }

    /// The file changed on disk: a log that grew is read on (and followed); one that was truncated or replaced
    /// (rotated) is read again from the start.
    public func fileDidChange() {
        guard let index, let url else { return }
        if index.file.isTruncated || !FileManager.default.fileExists(atPath: url.path) {
            self.index = nil
            load(url: url)
            return
        }
        guard index.file.grew() else { return }
        scan()
    }

    /// Stops reading (the tab was closed or the file left).
    public func stop() { index?.stop() }

    func scan() {
        index?.scan { [weak self] summary in self?.scanned(summary) }
    }

    private func scanned(_ summary: LogSummary) {
        let grew = summary.entryCount != (self.summary?.entryCount ?? 0)
        self.summary = summary
        updateCounts()
        guard grew else { return }
        if visible == nil {
            tableView.noteNumberOfRowsChanged()
            showEmptyStateIfNeeded()
            followIfOn()
        } else {
            refilter()
        }
    }

    func followIfOn() {
        guard followBox.state == .on, tableView.numberOfRows > 0 else { return }
        tableView.scrollRowToVisible(tableView.numberOfRows - 1)
    }

    // MARK: - Theme

    @objc func themeChanged() {
        applyTheme()
        tableView.reloadData()
    }

    public func applyTheme() {
        layer?.backgroundColor = Theme.background.cgColor
        summaryLabel.textColor = Theme.statusText
        hairline.layer?.backgroundColor = Theme.border.cgColor
        tableView.gridColor = Theme.rowSeparator
        detailView.backgroundColor = Theme.background
        detailView.textColor = Theme.foreground
        detailView.insertionPointColor = Theme.foreground
        split.needsDisplay = true
    }
}
