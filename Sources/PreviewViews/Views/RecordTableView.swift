//
//  RecordTableView.swift
//  Sidewatch
//
//  A line-oriented file — hosts, crontab, Procfile, ssh config, a gettext catalog — as a table
//  edited in place: each cell writes its own line back, disabled records dimmed and switchable.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import ThemedControls
import AppKitViews

/// Shows a `RecordTable`: a summary line, the columns, section rows spanning the table, a
/// switch per record that can be turned off (a commented-out hosts entry or cron job), and every
/// editable cell edited in place (double-click or ↩). An edit is handed to `onEdit` as the
/// document's NEW TEXT — the row's own line rewrite — so the owner replaces just what changed.
/// The find bar filters it like the other tables.
public final class RecordTableView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, PreviewFindable {
    /// The document's text after an edit; the owner writes it back.
    public var onEdit: ((_ newText: (String) -> String) -> Void)?
    /// Shows without editing: no cell edits and no enable switches (the Quick Look preview).
    public var isReadOnly = false

    private let tableView = NSTableView()
    private let scrollView = ThemedScrollView()
    private let summary = NSTextField(labelWithString: "")
    private let hairline = NSView()
    private let emptyState = EmptyStateView(symbol: "tablecells", title: "", subtitle: "")
    public private(set) var table = RecordTable(columns: [], rows: [], summary: "", empty: ("tablecells", "", ""))
    /// Indices into `table.rows` the filter leaves.
    private var visible: [Int] = []
    /// Bumped by every load; an edit records the load it began under.
    private var generation = 0
    private var editGeneration = 0
    private var query = ""
    /// Each row's cells joined, as written and lowercased — built once per load, so a filter
    /// keystroke over 50,000 rows is one substring search per row.
    private var haystacks: [String] = []
    private var lowerHaystacks: [String] = []
    private var queryCaseSensitive = false
    private static let toggleColumn = "enabled"

    public override init(frame: NSRect) { super.init(frame: frame); build() }
    public required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        summary.font = Theme.uiFontSmall
        hairline.wantsLayer = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        tableView.backgroundColor = .clear
        tableView.rowHeight = 24
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.allowsColumnReordering = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityLabel(String(localized: "Records", bundle: .module, comment: "Accessibility: the record table's name"))
        let menu = NSMenu()
        menu.addItem(String(localized: "Copy Cell", bundle: .module), action: #selector(copyCell), target: self)
        menu.addItem(String(localized: "Copy Row", bundle: .module), action: #selector(copyRow), target: self)
        tableView.menu = menu
        scrollView.documentView = tableView
        addSubviewsForAutoLayout(summary, hairline, scrollView)
        NSLayoutConstraint.activate([
            summary.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            summary.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            summary.topAnchor.constraint(equalTo: topAnchor, constant: 10),
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
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
    }

    /// Shows `table`. `keepingFilter` (an edit of the same file) keeps the find bar's filter and
    /// the scroll position.
    public func load(_ table: RecordTable, keepingFilter: Bool = false) {
        generation += 1  // an edit begun on the previous load must not land in this one's rows
        let columnsChanged = table.columns.map(\.id) != self.table.columns.map(\.id) || table.hasToggles != self.table.hasToggles
        // Emptied BEFORE the columns change: adding a column asks for the existing rows' cells,
        // and those rows belong to the previous file's shape.
        visible = []
        tableView.reloadData()
        self.table = table
        let prepared = table.haystacks.count == table.rows.count ? table : table.preparingSearch()
        haystacks = prepared.haystacks
        lowerHaystacks = prepared.lowerHaystacks
        if !keepingFilter { query = "" }
        if columnsChanged { rebuildColumns() }
        summary.stringValue = table.summary
        summary.setAccessibilityLabel(table.summary)
        applyFilter()
    }

    private func rebuildColumns() {
        for column in tableView.tableColumns { tableView.removeTableColumn(column) }
        tableView.headerView = ThemedTableHeaderView()
        if table.hasToggles {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.toggleColumn))
            column.headerCell = ThemedTableHeaderCell(title: "", titleInset: 6)
            column.width = 28
            column.minWidth = 28
            column.maxWidth = 28
            tableView.addTableColumn(column)
        }
        for spec in table.columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.title = spec.title
            column.headerCell = ThemedTableHeaderCell(title: spec.title, titleInset: 6)
            column.width = spec.width
            column.minWidth = 40
            tableView.addTableColumn(column)
        }
    }

    // MARK: - The find bar as a filter

    @discardableResult
    public func filter(_ text: String, caseSensitive: Bool) -> Int {
        if text == query, caseSensitive == queryCaseSensitive, !text.isEmpty { return matchCount }
        query = text
        queryCaseSensitive = caseSensitive
        applyFilter()
        if let first = visible.firstIndex(where: { table.rows[$0].section == nil }) {
            tableView.selectRowIndexes(IndexSet(integer: first), byExtendingSelection: false)
        }
        return matchCount
    }

    public func selectMatch(forward: Bool) {
        let records = visible.indices.filter { table.rows[visible[$0]].section == nil }
        guard !records.isEmpty else { return }
        let current = tableView.selectedRow
        let next: Int
        if forward {
            next = records.first { $0 > current } ?? records[0]
        } else {
            next = records.last { $0 < current } ?? records[records.count - 1]
        }
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    private var matchCount: Int { visible.filter { table.rows[$0].section == nil }.count }

    /// Records with any cell containing the query, each under its section row.
    private func applyFilter() {
        if query.isEmpty {
            visible = Array(table.rows.indices)
        } else {
            let needle = queryCaseSensitive ? query : query.lowercased()
            let pool = queryCaseSensitive ? haystacks : lowerHaystacks
            var out: [Int] = []
            var pendingSection: Int?
            for (i, row) in table.rows.enumerated() {
                if row.section != nil { pendingSection = i; continue }
                guard pool[i].contains(needle) else { continue }
                if let s = pendingSection { out.append(s); pendingSection = nil }
                out.append(i)
            }
            visible = out
        }
        tableView.reloadData()
        if table.rows.isEmpty {
            emptyState.show(symbol: table.empty.symbol, title: table.empty.title, subtitle: table.empty.subtitle)
        } else if matchCount == 0 {
            emptyState.show(
                symbol: "magnifyingglass", title: String(localized: "No Matches", bundle: .module),
                subtitle: String(
                    localized: "No cell contains “\(query)”.", bundle: .module,
                    comment: "record table: the find bar's filter matched nothing"))
        } else {
            emptyState.hide()
        }
    }

    // MARK: - Table

    public func numberOfRows(in tableView: NSTableView) -> Int { visible.count }

    public func tableView(_ tv: NSTableView, isGroupRow row: Int) -> Bool { record(at: row)?.section != nil }

    /// The record shown at table row `row`, or nil for a row the model no longer has.
    private func record(at row: Int) -> RecordTable.Row? {
        guard visible.indices.contains(row), table.rows.indices.contains(visible[row]) else { return nil }
        return table.rows[visible[row]]
    }

    public func tableView(_ tv: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ThemedRowView(accentBar: 3) }

    public func tableView(_ tv: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let record = record(at: row) else {
            staleCellRequestsForTesting += 1  // a row the current file does not have: the load order is wrong
            return nil
        }
        if let title = record.section {
            let label = NSTextField.label(title, font: NSFont.systemFont(ofSize: 11, weight: .semibold), color: Theme.statusText)
            let cell = NSTableCellView()
            cell.addSubviewsForAutoLayout(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
        guard let id = column?.identifier.rawValue else { return nil }
        if id == Self.toggleColumn {
            guard let enabled = record.enabled else { return nil }
            let box = ThemedCheckbox()
            box.isEnabled = !isReadOnly
            box.state = enabled ? .on : .off
            box.tag = row
            box.target = self
            box.action = #selector(toggled(_:))
            box.setAccessibilityLabel(
                String(localized: "Enabled", bundle: .module, comment: "record table: the switch that comments a line in or out"))
            let cell = NSTableCellView()
            cell.addSubviewsForAutoLayout(box)
            NSLayoutConstraint.activate([
                box.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                box.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
        guard let spec = table.columns.first(where: { $0.id == id }) else { return nil }
        let text = record.cells[id] ?? ""
        let dim = record.enabled == false
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.font = font(spec.style)
        field.textColor = color(spec.style, dim: dim, warning: record.warning != nil && id == "when")
        switch spec.style {
        case .chips:
            field.formatter = ChipsFormatter(
                font: field.font!, text: field.textColor!, fill: Theme.accent.withAlphaComponent(dim ? 0.06 : 0.14))
        case .tags:
            field.formatter = ChipsFormatter(
                font: Theme.uiFontSmall, text: Theme.statusText, fill: Theme.statusText.withAlphaComponent(0.16))
        default:
            field.formatter = CellEditFormatter()
        }
        field.objectValue = text
        if let warning = record.warning, id == "when" { field.toolTip = warning }
        if record.edits[id] != nil, !isReadOnly {
            field.isEditable = true
            field.isSelectable = true
            field.delegate = self
            field.focusRingType = .none
            field.disableSystemTextIntelligence()
        }
        field.tag = row
        field.identifier = NSUserInterfaceItemIdentifier(id)
        field.setAccessibilityLabel("\(spec.title): \(text)")
        let cell = NSTableCellView()
        cell.addSubviewsForAutoLayout(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func font(_ style: RecordTable.Style) -> NSFont {
        switch style {
        case .key: return .mono(12, weight: .medium)
        case .value, .code, .chips: return .mono(12)
        case .prose: return Theme.uiFont
        case .tags: return Theme.uiFontSmall
        }
    }

    private func color(_ style: RecordTable.Style, dim: Bool, warning: Bool) -> NSColor {
        if warning { return Theme.removed }
        let base: NSColor
        switch style {
        case .key: base = Theme.foreground
        case .value: base = Theme.string
        case .code, .chips: base = Theme.foreground
        case .prose, .tags: base = Theme.statusText
        }
        return dim ? base.withAlphaComponent(0.45) : base
    }

    // MARK: - Edits

    /// The load an edit began under: a field still editing when another file loads ends on rows of
    /// a different shape, and its row index would name the wrong record there.
    public func controlTextDidBeginEditing(_ n: Notification) { editGeneration = generation }

    /// An edited cell writes its line back when editing ends; nothing for the same text, nor for an
    /// edit begun before the table loaded another file.
    public func controlTextDidEndEditing(_ n: Notification) {
        guard let field = n.object as? NSTextField, let id = field.identifier?.rawValue, editGeneration == generation else { return }
        commit(row: field.tag, column: id, value: (field.objectValue as? String) ?? field.stringValue)
    }

    private func commit(row: Int, column id: String, value: String) {
        guard visible.indices.contains(row) else { return }
        let record = table.rows[visible[row]]
        guard let edit = record.edits[id], value != (record.cells[id] ?? "") else { tableView.reloadData(); return }
        onEdit?({ edit($0, value) })
    }

    @objc private func toggled(_ sender: NSButton) {
        guard visible.indices.contains(sender.tag), let toggle = table.rows[visible[sender.tag]].toggle else { return }
        let on = sender.state == .on
        onEdit?({ toggle($0, on) })
    }

    @objc private func copyCell() {
        let row = tableView.clickedRow, col = tableView.clickedColumn
        guard visible.indices.contains(row), col >= 0 else { return }
        NSPasteboard.general.copy(table.rows[visible[row]].cells[tableView.tableColumns[col].identifier.rawValue] ?? "")
    }

    @objc private func copyRow() {
        let row = tableView.clickedRow
        guard visible.indices.contains(row) else { return }
        let record = table.rows[visible[row]]
        NSPasteboard.general.copy(table.columns.map { record.cells[$0.id] ?? "" }.filter { !$0.isEmpty }.joined(separator: "\t"))
    }

    // MARK: - Harness

    /// Cell requests for a row the current file does not have — 0 unless a load reorders.
    public private(set) var staleCellRequestsForTesting = 0

    /// The cell text the table shows at `row` (an index into `table.rows`), for the harness.
    public func cellForTesting(row: Int, column: String) -> String? {
        table.rows.indices.contains(row) ? table.rows[row].cells[column] : nil
    }
    /// An edit as the field would deliver it, `row` indexing `table.rows`.
    public func commitEditForTesting(row: Int, column: String, value: String) {
        guard let index = visible.firstIndex(of: row) else { return }
        commit(row: index, column: column, value: value)
    }
    /// The switch as a click would leave it, `row` indexing `table.rows`.
    public func toggleForTesting(row: Int, on: Bool) {
        guard table.rows.indices.contains(row), let toggle = table.rows[row].toggle else { return }
        onEdit?({ toggle($0, on) })
    }
    /// How many rows the table shows, sections included.
    public var visibleRowCountForTesting: Int { tableView.numberOfRows }
    /// The drawn text of a visible cell, for the harness: `row` is a table row.
    public func renderedTextForTesting(row: Int, column: String) -> String? {
        guard let index = tableView.tableColumns.firstIndex(where: { $0.identifier.rawValue == column }),
            let cell = tableView.view(atColumn: index, row: row, makeIfNecessary: true)
        else { return nil }
        return cell.subviews.compactMap { $0 as? NSTextField }.first?.stringValue
    }
    /// Whether the empty state is up.
    public var emptyStateShownForTesting: Bool { !emptyState.isHidden }

    @objc private func themeChanged() { applyTheme(); tableView.reloadData() }

    public func applyTheme() {
        layer?.backgroundColor = Theme.background.cgColor
        summary.textColor = Theme.statusText
        hairline.layer?.backgroundColor = Theme.border.cgColor
        tableView.gridColor = Theme.rowSeparator
    }
}
