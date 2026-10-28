//
//  EnvTableView.swift
//  PreviewViews
//
//  A `.env` file as a Name / Value table, secrets shown as bullets until asked.
//
//  Created by David Sherlock on 9/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import AppKitViews
import DataConverter
import ThemedControls

/// A `.env` file as a two-column table: every `KEY=value` the loaders would read, in file
/// order, both columns editable in place, with the values `DotEnv.shouldMask` names
/// — secret words in the key, credentials in a URL — shown as bullets until the header's
/// "Show values" switch is on. A screen share or a screenshot of the preview leaks nothing by
/// default; Copy Value copies the real value, since copying is deliberate.
public final class EnvTableView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, PreviewFindable {
    private let tableView = NSTableView()
    /// True to show without editing (Quick Look): the cells stay selectable for copying but never
    /// open a field editor. Set before the first `load`.
    public var isReadOnly = false
    /// A value edited in the table: the entry as it was and the new value. The owner writes it
    /// into the source.
    public var onEdit: ((DotEnv.Entry, String) -> Void)?
    /// A NAME typed over in the table: the entry and the new name, already sanitised.
    public var onEditKey: ((DotEnv.Entry, String) -> Void)?
    /// The rows the find bar's query leaves visible (indices into `entries`); all of them
    /// without a query. A masked value is searched only while revealed, so a search cannot
    /// confirm what a bulleted value holds.
    private var visible: [Int] = []
    private var query = ""
    private var queryCaseSensitive = false
    private let scrollView = ThemedScrollView()
    private let summary = NSTextField(labelWithString: "")
    private let revealLabel = NSTextField(
        labelWithString: String(localized: "Show values", bundle: .module, comment: ".env preview switch: reveal masked secret values"))
    /// The header's "Show values" switch; hidden when nothing is masked.
    public let revealSwitch = ThemedSwitch()
    private let hairline = NSView()
    /// Every entry in file order; `visible` indexes into it.
    public private(set) var entries: [DotEnv.Entry] = []
    private var masked: [Bool] = []
    private var revealed = false
    /// A row's menu: Copy Name and Copy Value, then the copy items, built per click.
    private let rowMenu = NSMenu()
    /// The table's copy items (Copy Row, Copy as JSON / CSV / Markdown Table).
    let copier = TableCopier()
    /// Shown while a big file is read off the main thread (``beginLoading()``), once the read outlasts the loading
    /// state's delay; any load ends it.
    private let loadingState = LoadingStateView(caption: "")
    private let emptyState = EmptyStateView(
        symbol: "key", title: String(localized: "No Variables", bundle: .module),
        subtitle: String(localized: "This file has no KEY=value lines.", bundle: .module))
    /// A load that arrived while a cell was being edited, applied once the edit ends: `reloadData`
    /// under an open field editor ends the edit, and the typed value would land on whatever
    /// variable sits at that row afterwards.
    private var pendingLoad: (prepared: PreparedEntries, keepingReveal: Bool)?
    /// Whether a load is waiting for an edit to end, for the harness.
    public var hasPendingLoadForTesting: Bool { pendingLoad != nil }

    public override init(frame: NSRect) { super.init(frame: frame); build() }
    public required init?(coder: NSCoder) { fatalError() }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        summary.font = Theme.uiFontSmall
        revealLabel.font = Theme.uiFontSmall
        revealSwitch.controlSize = .small  // a header strip, not a settings row
        revealSwitch.target = self
        revealSwitch.action = #selector(revealChanged)
        revealSwitch.setAccessibilityLabel(
            String(localized: "Show values", bundle: .module, comment: ".env preview switch: reveal masked secret values"))
        hairline.wantsLayer = true

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        tableView.backgroundColor = .clear
        tableView.rowHeight = 24
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.gridColor = Theme.rowSeparator
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (id, title, width) in [
            ("name", String(localized: "Name", bundle: .module, comment: ".env preview column: the variable's name"), CGFloat(220)),
            ("value", String(localized: "Value", bundle: .module, comment: ".env preview column: the variable's value"), CGFloat(400)),
        ] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            col.minWidth = 80
            tableView.addTableColumn(col)
        }
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = true
        tableView.menu = rowMenu
        rowMenu.delegate = self
        scrollView.documentView = tableView
        wireCopier()
        addSubviewsForAutoLayout(summary, revealLabel, revealSwitch, hairline, scrollView)
        NSLayoutConstraint.activate([
            summary.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            summary.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            revealSwitch.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            revealSwitch.centerYAnchor.constraint(equalTo: summary.centerYAnchor),
            revealLabel.trailingAnchor.constraint(equalTo: revealSwitch.leadingAnchor, constant: -8),
            revealLabel.centerYAnchor.constraint(equalTo: summary.centerYAnchor),
            hairline.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 9),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
            scrollView.topAnchor.constraint(equalTo: hairline.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        emptyState.install(over: scrollView)
        loadingState.install(over: scrollView)
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    /// Parses `text` and shows it. The reveal switch goes back OFF for a new file; an edit of
    /// the same file (`keepingReveal`) keeps it, and keeps the find bar's filter.
    public func load(_ text: String, keepingReveal: Bool = false) {
        load(prepared: Self.prepare(text), keepingReveal: keepingReveal)
    }

    /// A file's variables and which of them are masked, read ahead of ``load(prepared:keepingReveal:)``: off the main
    /// thread for a big file.
    nonisolated public struct PreparedEntries: Sendable {
        let entries: [DotEnv.Entry]
        let masked: [Bool]
    }

    /// `text`'s variables, ready for ``load(prepared:keepingReveal:)``; callable from any thread.
    public nonisolated static func prepare(_ text: String) -> PreparedEntries {
        let entries = DotEnv.parse(text)
        return PreparedEntries(entries: entries, masked: entries.map { DotEnv.shouldMask(key: $0.key, value: $0.value) })
    }

    /// ``load(_:keepingReveal:)`` with the variables already read.
    public func load(prepared: PreparedEntries, keepingReveal: Bool = false) {
        if editingField != nil {
            pendingLoad = (prepared, keepingReveal)
            return
        }
        pendingLoad = nil
        apply(prepared, keepingReveal: keepingReveal)
    }

    /// A file is being read off the main thread: the table empties, says nothing about the file yet, and shows
    /// "Reading .env…" once the read outlasts a moment. The ``load(prepared:keepingReveal:)`` that follows ends it.
    public func beginLoading() {
        pendingLoad = nil
        entries = []
        masked = []
        visible = []
        tableView.reloadData()
        summary.stringValue = ""
        revealLabel.isHidden = true
        revealSwitch.isHidden = true
        emptyState.hide()
        loadingState.caption = PreviewReading.caption(".env")
        loadingState.begin()
    }

    /// Whether the table is waiting on a read begun by ``beginLoading()``, for tests and harnesses.
    public var isLoading: Bool { loadingState.isLoading }

    /// The load itself, once no field editor is open over the table.
    private func apply(_ prepared: PreparedEntries, keepingReveal: Bool) {
        loadingState.end()
        entries = prepared.entries
        masked = prepared.masked
        if !keepingReveal {
            revealed = false
            revealSwitch.state = .off
            query = ""
        }
        applyFilter()
        let hidden = masked.filter { $0 }.count
        summary.stringValue =
            entries.isEmpty
            ? ""
            : hidden > 0
                ? String(
                    localized: "\(entries.count) variables · \(hidden) masked",
                    comment: ".env preview summary: how many variables, how many have hidden values")
                : String(localized: "\(entries.count) variables", bundle: .module, comment: ".env preview summary: how many variables")
        revealLabel.isHidden = hidden == 0
        revealSwitch.isHidden = hidden == 0
    }

    /// The value as the row shows it now: bullets while masked and not revealed. `row` is an
    /// index into `entries`, filter or no filter.
    public func displayedValue(row: Int) -> String {
        guard entries.indices.contains(row) else { return "" }
        return masked[row] && !revealed ? DotEnv.mask : entries[row].value
    }

    // MARK: - The find bar as a filter

    /// Keeps the rows whose name or shown value contains `text` (every row for an empty query)
    /// and returns how many — the find bar's count. The first match is selected.
    @discardableResult
    public func filter(_ text: String, caseSensitive: Bool) -> Int {
        if text == query, caseSensitive == queryCaseSensitive, !text.isEmpty { return visible.count }  // ▲ ▼ keep the selection
        query = text
        queryCaseSensitive = caseSensitive
        applyFilter()
        if !visible.isEmpty { tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        return visible.count
    }

    /// The next or previous visible row, wrapping — the find bar's ▲ ▼.
    public func selectMatch(forward: Bool) {
        guard !visible.isEmpty else { return }
        let current = tableView.selectedRow
        let next = current < 0 ? 0 : (forward ? (current + 1) % visible.count : (current - 1 + visible.count) % visible.count)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    /// Selects and scrolls to the variable on 1-based source `line` (an outline click); false when
    /// no shown row is that line.
    @discardableResult
    public func reveal(line: Int) -> Bool {
        guard let row = visible.firstIndex(where: { entries[$0].line == line }) else { return false }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        return true
    }

    /// The selected row's variable, for the harness.
    public var selectedEntryForTesting: DotEnv.Entry? { entry(atRow: tableView.selectedRow) }

    /// Selects `rows` (indexes of the rows shown), as clicks would, for tests.
    public func selectRowsForTesting(_ rows: [Int]) { tableView.selectRowIndexes(IndexSet(rows), byExtendingSelection: false) }

    /// The visible rows' names, in order, for the harness.
    public var visibleKeys: [String] { visible.map { entries[$0].key } }

    private func applyFilter() {
        if query.isEmpty {
            visible = Array(entries.indices)
        } else {
            visible = entries.indices.filter { i in
                DotEnv.matches(entries[i], query: query, caseSensitive: queryCaseSensitive, valueIsSearchable: revealed || !masked[i])
            }
        }
        tableView.reloadData()
        if entries.isEmpty {
            emptyState.show(
                symbol: "key", title: String(localized: "No Variables", bundle: .module),
                subtitle: String(localized: "This file has no KEY=value lines.", bundle: .module))
        } else if visible.isEmpty {
            emptyState.show(
                symbol: "magnifyingglass", title: String(localized: "No Matches", bundle: .module),
                subtitle: String(localized: "No name or shown value contains “\(query)”.", bundle: .module))
        } else {
            emptyState.hide()
        }
    }

    /// Whether the empty state is up, for the harness.
    public var emptyStateShownForTesting: Bool { !emptyState.isHidden }

    @objc private func revealChanged() {
        revealed = revealSwitch.state == .on
        applyFilter()
    }

    /// The switch as a click would leave it, for the harness.
    public func setRevealForTesting(_ on: Bool) {
        revealSwitch.state = on ? .on : .off
        revealChanged()
    }

    @objc private func copyName() { put(entry(atRow: tableView.clickedRow)?.key) }
    @objc private func copyValue() { put(entry(atRow: tableView.clickedRow)?.value) }
    private func entry(atRow row: Int) -> DotEnv.Entry? { visible.indices.contains(row) ? entries[visible[row]] : nil }

    // MARK: - Editing

    /// The edit lands when the field ends editing (↩ or focus out); nothing changes for the
    /// same text. The typed text comes from `objectValue` — the formatter put it there
    /// undecorated, while `stringValue` would hand back the bullets a masked row draws.
    public func controlTextDidEndEditing(_ n: Notification) {
        defer { replayPendingLoad() }
        guard let field = n.object as? NSTextField, let entry = entry(atRow: field.tag) else { return }
        let typed = (field.objectValue as? String) ?? field.stringValue
        // The variable as the text a held-back load carries names it: an outside insert above
        // moved it to another line, and the host writes by line.
        let target = pendingLoad.map { DotEnv.entry(matching: entry, among: entries, in: $0.prepared.entries) } ?? entry
        if field.identifier?.rawValue == "name" {
            let clean = DotEnv.sanitisedKey(typed)
            guard !clean.isEmpty, clean != entry.key else { tableView.reloadData(); return }
            onEditKey?(target, clean)
            return
        }
        guard typed != DotEnv.mask, typed != entry.value else { tableView.reloadData(); return }
        onEdit?(target, typed)
    }

    /// The cell whose field editor holds the keyboard, or nil.
    private var editingField: NSTextField? {
        guard let editor = window?.firstResponder as? NSTextView, let field = editor.delegate as? NSTextField,
            field.isDescendant(of: tableView)
        else { return nil }
        return field
    }

    /// Applies the load an edit held back, a turn later: the end-editing notification arrives
    /// while the field editor still holds the keyboard, and a reload under it is the bug avoided.
    private func replayPendingLoad() {
        guard pendingLoad != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let pending = self.pendingLoad, self.editingField == nil else { return }
            self.pendingLoad = nil
            self.apply(pending.prepared, keepingReveal: pending.keepingReveal)
        }
    }

    /// Opens a row's name (0) or value (1) cell for editing, as a double-click does; false when
    /// the row has no cell. For the harness.
    @discardableResult
    public func beginEditForTesting(row: Int, column: Int) -> Bool {
        guard let shown = visible.firstIndex(of: row), let cell = tableView.view(atColumn: column, row: shown, makeIfNecessary: true),
            let field = cell.subviews.compactMap({ $0 as? NSTextField }).first, let window
        else { return false }
        return window.makeFirstResponder(field)
    }
    /// Commits whatever the open editor holds, as clicking away does. For the harness.
    public func endEditForTesting() { window?.makeFirstResponder(tableView) }

    /// What the field editor would show for a row's value — the real value even while the row
    /// draws bullets (for the harness; a masked value typed over as bullets was the risk).
    public func editorTextForTesting(row: Int) -> String? {
        guard entries.indices.contains(row),
            let cell = tableView.view(atColumn: 1, row: row, makeIfNecessary: true),
            let field = cell.subviews.compactMap({ $0 as? NSTextField }).first
        else { return nil }
        return field.formatter?.editingString(for: field.objectValue as Any) ?? field.stringValue
    }
    /// What the row DRAWS for its value, for the harness.
    public func displayedTextForTesting(row: Int) -> String? {
        guard entries.indices.contains(row),
            let cell = tableView.view(atColumn: 1, row: row, makeIfNecessary: true),
            let field = cell.subviews.compactMap({ $0 as? NSTextField }).first
        else { return nil }
        return field.stringValue
    }

    /// The key edit a name field would deliver, for the harness.
    public func commitKeyEditForTesting(row: Int, key: String) {
        guard entries.indices.contains(row) else { return }
        let clean = DotEnv.sanitisedKey(key)
        guard !clean.isEmpty else { return }
        onEditKey?(entries[row], clean)
    }

    /// The edit a field would deliver on end-editing, for the harness. `row` indexes `entries`.
    public func commitEditForTesting(row: Int, value: String) {
        guard entries.indices.contains(row) else { return }
        onEdit?(entries[row], value)
    }
    private func put(_ s: String?) {
        guard let s else { return }
        NSPasteboard.general.copy(s)
    }

    @objc private func themeChanged() { applyTheme(); tableView.reloadData() }

    public func applyTheme() {
        layer?.backgroundColor = Theme.background.cgColor
        summary.textColor = Theme.statusText
        revealLabel.textColor = Theme.statusText
        hairline.layer?.backgroundColor = Theme.border.cgColor
        tableView.gridColor = Theme.rowSeparator
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { visible.count }

    public func tableView(_ tv: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard visible.indices.contains(row) else { return nil }
        let index = visible[row]
        let isName = column?.identifier.rawValue == "name"
        let text = isName ? entries[index].key : displayedValue(row: index)
        let label = NSTextField.label(
            text, font: .mono(12, weight: isName ? .medium : .regular),
            color: isName ? Theme.foreground : (masked[index] && !revealed ? Theme.statusText : Theme.string),
            lineBreak: .byTruncatingTail)
        // BOTH columns edit in place, the name as well as the value. Double-click (or ↩ on the
        // row); the field editor is the window's configured one, so autocorrect and Writing
        // Tools stay out.
        label.isEditable = !isReadOnly
        label.isSelectable = true
        label.delegate = self
        label.tag = row
        label.focusRingType = .none
        label.disableSystemTextIntelligence()
        // The row draws the bullets while the value is masked, the EDITOR loads the real value
        // — through a formatter, because swapping `stringValue` when editing begins does not
        // reach the field editor.
        label.formatter = (!isName && masked[index] && !revealed) ? CellEditFormatter(substitute: DotEnv.mask) : CellEditFormatter()
        label.objectValue = isName ? entries[index].key : entries[index].value
        label.identifier = NSUserInterfaceItemIdentifier(isName ? "name" : "value")
        let cell = NSTableCellView()
        cell.addSubviewsForAutoLayout(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    public func tableView(_ tv: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { tv.reusableView { ThemedRowView(accentBar: 3) } }
}

// MARK: - Copying

extension EnvTableView: NSMenuDelegate {
    /// Points the copy items at the variables shown, each value as its row shows it: a hidden value stays bullets
    /// unless Show values is on, so rows copied for an agent do not carry secrets by accident. Copy Value, on one row,
    /// is the way to the value itself.
    fileprivate func wireCopier() {
        copier.host = self
        copier.columns = { [String(localized: "Name", bundle: .module), String(localized: "Value", bundle: .module)] }
        copier.rows = { [unowned self] in
            self.tableView.actionRows().compactMap { row -> [TableCell]? in
                guard self.visible.indices.contains(row) else { return nil }
                let index = self.visible[row]
                return [.text(self.entries[index].key), .text(self.displayedValue(row: index))]
            }
        }
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let rows = tableView.actionRows().count
        if tableView.clickedRow >= 0 {
            menu.addItem(String(localized: "Copy Name", bundle: .module), action: #selector(copyName), target: self)
            menu.addItem(String(localized: "Copy Value", bundle: .module), action: #selector(copyValue), target: self)
            menu.addItem(.separator())
        }
        copier.addItems(to: menu, rowCount: rows)
    }

    /// Edit ▸ Copy over the table: the selected variables as tab-separated text, hidden values as bullets; a beep with
    /// none selected.
    @objc public func copy(_ sender: Any?) {
        if !copier.copySelection() { NSSound.beep() }
    }
}
