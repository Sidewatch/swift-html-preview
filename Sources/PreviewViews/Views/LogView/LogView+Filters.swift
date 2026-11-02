//
//  LogView+Filters.swift
//  PreviewViews
//
//  LogView: the bar's filters (levels, components, time, follow), the counts, and running the filter.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import FoundationExtensions
import LogReader
import ThemedControls

extension LogView {
    // MARK: - Actions

    @objc func levelBoxClicked(_ sender: ThemedCheckbox) {
        if sender.tag < 0 {
            filter.showsUnleveled = sender.state == .on
        } else if let level = LogLevel(rawValue: sender.tag) {
            if sender.state == .on { filter.levels.insert(level) } else { filter.levels.remove(level) }
        }
        refilter()
    }

    @objc func followClicked() { followIfOn() }

    @objc func componentChosen(_ item: NSMenuItem) {
        let all = summary?.components.map(\.name) ?? []
        if let name = item.representedObject as? String {
            var chosen = filter.components ?? []
            if filter.components == nil {
                chosen = [name]  // from all: only this one
            } else if chosen.contains(name) {
                chosen.remove(name)
            } else {
                chosen.insert(name)
            }
            filter.components = chosen.isEmpty || chosen.count == all.count ? nil : chosen
        } else {
            filter.components = nil
        }
        syncControls()
        refilter()
    }

    @objc func timeChosen(_ item: NSMenuItem) {
        timeWindow = item.tag > 0 ? .last(TimeInterval(item.tag)) : .all
        syncControls()
        refilter()
    }

    // MARK: - Running the filter

    /// Runs the filter off the main thread and shows what it lets through; a run asked for while one is going runs
    /// after it, and a run the filter moved on from is dropped.
    func refilter() {
        applyTimeWindow()
        guard !filter.isEmpty else {
            filterGeneration += 1
            showRows(nil)
            return
        }
        guard let index else { return }
        guard !filtering else {
            refilterPending = true
            return
        }
        filtering = true
        filterGeneration += 1
        let generation = filterGeneration
        Self.match(index, filter) { [weak self] result in
            guard let self else { return }
            self.filtering = false
            if generation == self.filterGeneration, let result {
                self.showRows(result)
                if !self.filter.text.isEmpty { self.onMatchCount?(result.count) }
            }
            if self.refilterPending {
                self.refilterPending = false
                self.refilter()
            }
        }
    }

    /// The filter on a background queue; `done` on the main actor. Nonisolated, so the background closure is not a
    /// main-actor one (which would trap off the main thread).
    nonisolated static func match(_ index: LogIndex, _ filter: LogFilter, done: @escaping @MainActor ([Int]?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = index.matching(filter)
            DispatchQueue.main.async { MainActor.assumeIsolated { done(result) } }
        }
    }

    /// Shows `rows` (nil: every entry), keeping the selected entries selected where they still show.
    private func showRows(_ rows: [Int]?) {
        let selected = tableView.selectedRowIndexes.compactMap { entryIndex(forRow: $0) }
        visible = rows
        tableView.reloadData()
        let keep = IndexSet(selected.compactMap { row(forEntry: $0) })
        tableView.selectRowIndexes(keep, byExtendingSelection: false)
        if let first = keep.first { tableView.scrollRowToVisible(first) } else { followIfOn() }
        showSelectedEntry()
        showEmptyStateIfNeeded()
        updateSummaryText()
    }

    /// The time window as the filter's bounds: the last stretch before the newest entry, or a picked range.
    func applyTimeWindow() {
        switch timeWindow {
        case .all:
            filter.from = nil
            filter.to = nil
        case .last(let span):
            filter.from = summary?.lastTime.map { $0 - span }
            filter.to = nil
        case .range(let from, let to):
            filter.from = from
            filter.to = to
        }
    }

    // MARK: - Counts and controls

    /// Each level box's count (a box shows only when its level occurs), the menus, and the summary line.
    func updateCounts() {
        guard let summary else { return }
        for (level, box) in levelBoxes {
            let count = summary.levelCounts[level] ?? 0
            box.title = "\(Self.levelTitle(level)) \(count.grouped)"
            box.isHidden = count == 0
        }
        unleveledBox.title = String(
            localized: "Other \(summary.unleveledCount.grouped)", bundle: .module, comment: "Log view: entries with no level, and how many")
        unleveledBox.isHidden = summary.unleveledCount == 0 || summary.unleveledCount == summary.entryCount
        syncControls()
        updateSummaryText()
        showEmptyStateIfNeeded()
    }

    /// The menus' titles and items, from the filter and the summary; a menu with nothing to choose hides.
    func syncControls() {
        for (level, box) in levelBoxes { box.state = filter.levels.contains(level) ? .on : .off }
        unleveledBox.state = filter.showsUnleveled ? .on : .off
        buildComponentMenu()
        buildTimeMenu()
    }

    private func buildComponentMenu() {
        let components = summary?.components ?? []
        componentButton.isHidden = components.count < 2
        let menu = NSMenu()
        let title: String
        if let chosen = filter.components {
            title =
                chosen.count == 1
                ? chosen.first!
                : String(localized: "\(chosen.count) Components", bundle: .module, comment: "Log view: how many components are shown")
        } else {
            title = String(localized: "All Components", bundle: .module, comment: "Log view: every component shown")
        }
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")  // a pull-down's title item
        let all = menu.addItem(
            withTitle: String(localized: "All Components", bundle: .module, comment: "Log view: every component shown"),
            action: #selector(componentChosen(_:)), keyEquivalent: "")
        all.target = self
        all.state = filter.components == nil ? .on : .off
        menu.addItem(.separator())
        for component in components.prefix(200) {
            let item = menu.addItem(
                withTitle: "\(component.name)  \(component.count.grouped)", action: #selector(componentChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = component.name
            item.state = filter.components?.contains(component.name) == true ? .on : .off
        }
        componentButton.menu = menu
    }

    private func buildTimeMenu() {
        timeButton.isHidden = summary?.lastTime == nil
        let menu = NSMenu()
        let windows: [(String, Int)] = [
            (String(localized: "All Time", bundle: .module, comment: "Log view: no time filter"), 0),
            (String(localized: "Last 5 Minutes", bundle: .module, comment: "Log view: the last 5 minutes before the newest entry"), 300),
            (String(localized: "Last 15 Minutes", bundle: .module, comment: "Log view: time filter"), 900),
            (String(localized: "Last Hour", bundle: .module, comment: "Log view: time filter"), 3600),
            (String(localized: "Last 24 Hours", bundle: .module, comment: "Log view: time filter"), 86_400),
        ]
        var title = windows[0].0
        switch timeWindow {
        case .all: break
        case .last(let span): title = windows.first { $0.1 == Int(span) }?.0 ?? title
        case .range: title = String(localized: "Picked Range", bundle: .module, comment: "Log view: a time range picked from entries")
        }
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        for (name, seconds) in windows {
            let item = menu.addItem(withTitle: name, action: #selector(timeChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            item.state = (seconds == 0 && timeWindow == .all) || timeWindow == .last(TimeInterval(seconds)) ? .on : .off
        }
        timeButton.menu = menu
    }

    /// `1,234 of 512,161 entries · plain, JSON lines`, and `· reading…` until the scan is done.
    func updateSummaryText() {
        guard let summary else {
            summaryLabel.stringValue = ""
            return
        }
        let total = summary.entryCount
        var parts = [
            visible.map {
                String(
                    localized: "\($0.count.grouped) of \(total.grouped) entries", bundle: .module, comment: "Log view: entries shown of all"
                )
            } ?? String(localized: "\(total.grouped) entries", bundle: .module, comment: "Log view: how many entries the log has")
        ]
        let formats = summary.formats.filter { $0 != .text }.prefix(3).map(Self.formatName)
        if !formats.isEmpty { parts.append(formats.joined(separator: ", ")) }
        if !summary.isComplete {
            parts.append(String(localized: "reading…", bundle: .module, comment: "Log view: the file is still being read"))
        }
        summaryLabel.stringValue = parts.joined(separator: " · ")
    }

    func showEmptyStateIfNeeded() {
        let rows = tableView.numberOfRows
        guard rows == 0 else {
            emptyState.isHidden = true
            return
        }
        emptyState.isHidden = false
        if (summary?.entryCount ?? 0) == 0 {
            let reading = summary?.isComplete != true
            emptyState.setText(
                title: reading
                    ? String(localized: "Reading…", bundle: .module, comment: "Log view: the file is being read")
                    : String(localized: "Empty Log", bundle: .module, comment: "Log view: the file has no entries"),
                subtitle: "")
        } else {
            emptyState.setText(
                title: String(localized: "No Entries Match", bundle: .module, comment: "Log view: the filters let nothing through"),
                subtitle: String(
                    localized: "Turn a level back on, or widen the time or component.", bundle: .module,
                    comment: "Log view: how to see entries again"))
        }
    }

    /// A format's name for the summary line.
    static func formatName(_ format: LogFormat) -> String {
        switch format {
        case .plain: return String(localized: "plain", bundle: .module, comment: "Log format: timestamped plain lines")
        case .json: return String(localized: "JSON lines", bundle: .module, comment: "Log format")
        case .dockerJSON: return "Docker JSON"
        case .logfmt: return "logfmt"
        case .syslog5424: return "syslog (RFC 5424)"
        case .syslog: return "syslog"
        case .appleUnified: return String(localized: "macOS log", bundle: .module, comment: "Log format: macOS's unified log")
        case .rubyLogger: return "Ruby Logger"
        case .klog: return "klog"
        case .logcat: return "logcat"
        case .monolog: return "Laravel / Monolog"
        case .phpError: return String(localized: "PHP error log", bundle: .module, comment: "Log format")
        case .apacheError: return String(localized: "Apache error log", bundle: .module, comment: "Log format")
        case .accessLog: return String(localized: "access log", bundle: .module, comment: "Log format: web server access log")
        case .nginxError: return String(localized: "nginx error log", bundle: .module, comment: "Log format")
        case .goLog: return "Go log"
        case .redis: return "Redis"
        case .elixir: return "Elixir Logger"
        case .javaUtilLogging: return "java.util.logging"
        case .pythonBasic: return "Python logging"
        case .text: return String(localized: "text", bundle: .module, comment: "Log format: lines with no header")
        }
    }
}
