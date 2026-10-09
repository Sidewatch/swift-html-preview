//
//  CSVTableView.swift
//  Sidewatch
//
//  Native spreadsheet preview for CSV: real columns from the header row, quote-aware parsing,
//  the find bar's query as the row filter, and cells edited in place.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import ThemedControls
import DataConverter
import AppKitViews

/// Native spreadsheet preview for CSV — real columns from the header row, quote-aware parsing
/// (DataConverter), the find bar's query as the row filter (the one search, as for .env and
/// YAML), header-click sorting, and cells EDITED IN PLACE: the value a cell ends with goes out
/// through `onEdit` as the file's record and column, and the host rewrites that one field in the
/// buffer (`CSVEdit`) as one undo step.
public final class CSVTableView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, PreviewFindable, CellTabbing {
    private let tableView = InnerGridTableView()
    private let scrollView = ThemedScrollView()
    private let cellFont = NSFont.mono(11)
    /// A cell's edit: the file's record (1-based data row → its 0-based record, the header being 0),
    /// the column, the new value.
    public var onEdit: ((_ record: Int, _ column: Int, _ value: String) -> Void)?
    /// Shows without editing: cells stay labels (the Quick Look preview).
    public var isReadOnly = false

    private var headers: [String] = []
    private var allRows: [[String]] = []
    private var rows: [[String]] = []
    /// For each shown row, its index in `allRows` — the filter and the sort permute both together,
    /// so an edit lands on the record the person sees.
    private var rowIndices: [Int] = []
    /// The find bar's query, the row filter.
    private var query = ""
    /// Parse cache: `load` also runs on doc-neutral refreshes (theme flips, split
    /// re-hosts, PreviewController hash collisions), so identical source must not
    /// re-tokenize the whole file. Keyed by the source string itself — equality is
    /// O(1) for the common same-storage re-render and still far cheaper than a
    /// re-parse otherwise; the string is COW so this holds a reference, not a copy.
    private var cachedSource: String?
    private var cachedRecords: [[String]] = []
    /// A load that arrived while a cell was being edited, applied once the edit ends: `reloadData`
    /// under an open field editor ends the edit with the typed value lost.
    private var pendingLoad: (csv: String, keepingFilter: Bool)?
    /// Whether a load is waiting for an edit to end, for the harness.
    public var hasPendingLoadForTesting: Bool { pendingLoad != nil }
    /// Shown over the table when a loaded CSV has no header row and no data rows.
    private let emptyState = EmptyStateView(
        symbol: "tablecells", title: String(localized: "Empty CSV", bundle: .module),
        subtitle: String(localized: "This file has no rows to display.", bundle: .module))

    public override init(frame: NSRect) { super.init(frame: frame); build() }
    public required init?(coder: NSCoder) { fatalError() }

    /// Wires up the scroll view and table and pins them via Auto Layout. Must set
    /// `translatesAutoresizingMaskIntoConstraints = false` or PreviewController's edge pins
    /// conflict and the table renders blank.
    private func build() {
        translatesAutoresizingMaskIntoConstraints = false  // PreviewController pins edge constraints
        styleLayer(background: Theme.background)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        tableView.backgroundColor = .clear
        tableView.rowHeight = 22
        tableView.usesAlternatingRowBackgroundColors = false
        // Horizontal lines are AppKit's; the VERTICAL ones are drawn by `InnerGridTableView`,
        // one between each pair of columns and none on the table's own edges — the stock mask
        // rules every boundary including the outer two, which puts a line down the first column's
        // left where nothing is being divided.
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        // Grid lines are inner dividers, so they lift toward the foreground rather
        // than using the recessed `Theme.border` (darker than the background on
        // dark themes, which drew the grid as dark gashes across the table).
        tableView.gridColor = Theme.rowSeparator
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.dataSource = self
        tableView.delegate = self
        scrollView.documentView = tableView
        addPinnedSubview(scrollView)

        emptyState.install(over: scrollView)
    }

    /// Parses raw CSV text (first record = header row), resets the filter unless
    /// `keepingFilter` (an edit re-renders the same document and must not lose the query),
    /// and rebuilds the columns + table. Entry point called by PreviewController.
    public func load(_ csv: String, keepingFilter: Bool = false) {
        if editingField != nil {
            pendingLoad = (csv, keepingFilter)
            return
        }
        pendingLoad = nil
        apply(csv, keepingFilter: keepingFilter)
    }

    /// The load itself, once no field editor is open over the table.
    private func apply(_ csv: String, keepingFilter: Bool) {
        let records = records(of: csv)
        headers = records.first ?? []
        allRows = Array(records.dropFirst())
        rows = allRows
        rowIndices = Array(allRows.indices)
        if !keepingFilter {
            query = ""
            tableView.sortDescriptors = []  // a fresh file starts in file order
        }
        rebuildColumns()
        if keepingFilter { applyFilterAndSort() } else { tableView.reloadData() }
        if headers.isEmpty && rows.isEmpty {
            emptyState.show(
                symbol: "tablecells", title: String(localized: "Empty CSV", bundle: .module),
                subtitle: String(localized: "This file has no rows to display.", bundle: .module))
        } else {
            emptyState.hide()
        }
    }

    /// `csv`'s records, through the parse cache.
    private func records(of csv: String) -> [[String]] {
        if csv == cachedSource { return cachedRecords }
        let records = DataConverter.csvRecords(csv)
        cachedSource = csv
        cachedRecords = records
        return records
    }

    /// Rebuilds table columns for the current headers, prepending a row-index "#" column.
    /// Column widths are sized to fit the header + a sample of the first 60 rows, clamped
    /// to 60…380pt to keep very wide values from dominating the layout.
    private func rebuildColumns() {
        for col in tableView.tableColumns { tableView.removeTableColumn(col) }
        // Swapped in every rebuild: the header view is recreated with the columns, so themeing it
        // once at init would be undone the next time a CSV is loaded.
        tableView.headerView = ThemedTableHeaderView()
        let idxCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("#"))
        idxCol.title = "#"
        idxCol.width = 46
        idxCol.headerCell = ThemedTableHeaderCell(title: "#")
        // Sorting the row counter means "original order" (or reversed) — the escape hatch
        // back from any column sort.
        idxCol.sortDescriptorPrototype = NSSortDescriptor(key: "#", ascending: true)
        tableView.addTableColumn(idxCol)
        for (i, h) in headers.enumerated() {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(i)"))
            col.title = h
            col.headerCell = ThemedTableHeaderCell(title: h)
            // The fitted width is only the STARTING width — the mask is what makes the
            // divider draggable, and without it a wide value is simply unreadable forever.
            col.resizingMask = .userResizingMask
            col.minWidth = 40
            col.maxWidth = 4000
            col.sortDescriptorPrototype = NSSortDescriptor(key: "c\(i)", ascending: true)
            var w = (h as NSString).size(withAttributes: [.font: cellFont]).width + 26
            for r in allRows.prefix(60) where i < r.count {
                w = max(w, (r[i] as NSString).size(withAttributes: [.font: cellFont]).width + 26)
            }
            col.width = min(380, max(60, w))
            tableView.addTableColumn(col)
        }
    }

    private var filterCaseSensitive = false
    /// The find bar's query as the row filter — one instrument for every preview. Returns the
    /// rows left, the first selected.
    @discardableResult
    public func filter(_ text: String, caseSensitive: Bool) -> Int {
        if text == query, caseSensitive == filterCaseSensitive, !text.isEmpty { return rows.count }  // ▲ ▼ keep the selection
        query = text
        filterCaseSensitive = caseSensitive
        applyFilterAndSort()
        if !rows.isEmpty, !text.isEmpty { tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        return rows.count
    }
    /// ▲ ▼: selects the next or previous shown row, wrapping.
    public func selectMatch(forward: Bool) {
        guard !rows.isEmpty else { return }
        let current = tableView.selectedRow
        let next = current < 0 ? 0 : (forward ? (current + 1) % rows.count : (current - 1 + rows.count) % rows.count)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }
    /// The rows shown, and whether the empty state is up, for the harness.
    public var shownRowCountForTesting: Int { rows.count }
    public var emptyStateShownForTesting: Bool { !emptyState.isHidden }

    /// Header-click sorting. The table manages the descriptors and the indicator arrows;
    /// this just recomputes the visible rows.
    public func tableView(_ tv: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        applyFilterAndSort()
    }

    /// Filter, then sort — ONE pipeline, so searching while sorted (or sorting while
    /// filtered) composes instead of each stomping the other's result.
    private func applyFilterAndSort() {
        let q = filterCaseSensitive ? query : query.lowercased()
        // Rows travel with their file positions so a sort or a filter never detaches an edit
        // from the record it was made on.
        var out: [(row: [String], index: Int)] = allRows.enumerated().map { ($0.element, $0.offset) }
        if !q.isEmpty { out = out.filter { $0.row.contains { (filterCaseSensitive ? $0 : $0.lowercased()).contains(q) } } }
        if let d = tableView.sortDescriptors.first, let key = d.key {
            if key == "#" {
                if !d.ascending { out.reverse() }  // the row counter = original order
            } else if let ci = Int(key.dropFirst()) {
                // Decorate with the original position so equal cells keep their file order —
                // Swift's sort is not stable, and a viewer that shuffles ties on every click
                // reads as broken.
                out = out.enumerated()
                    .sorted { a, b in
                        let r = CellOrder.compare(
                            a.element.row.indices.contains(ci) ? a.element.row[ci] : "",
                            b.element.row.indices.contains(ci) ? b.element.row[ci] : "")
                        if r != .orderedSame {
                            return d.ascending
                                ? r == .orderedAscending
                                : r == .orderedDescending
                        }
                        return a.offset < b.offset
                    }
                    .map(\.element)
            }
        }
        rows = out.map(\.row)
        rowIndices = out.map(\.index)
        tableView.reloadData()
        if rows.isEmpty, !allRows.isEmpty, !query.isEmpty {
            emptyState.show(
                symbol: "magnifyingglass", title: String(localized: "No Matches", bundle: .module),
                subtitle: String(localized: "No cell contains “\(query)”.", bundle: .module))
        } else if !(headers.isEmpty && allRows.isEmpty) {
            emptyState.hide()
        }
    }

    // MARK: - Editing

    // MARK: - Tab between cells

    /// Every data cell, in reading order. `tag` is the TABLE column (0 is the row counter, which
    /// is a label, so the data starts at 1).
    public var editableCells: [CellPosition] {
        guard tableView.numberOfColumns > 1 else { return [] }
        return (0..<tableView.numberOfRows).flatMap { row in
            (1..<tableView.numberOfColumns).map { CellPosition(row: row, tag: $0) }
        }
    }

    /// Opens a cell for editing — used by Tab, and by the harness.
    public func beginEditing(_ position: CellPosition) {
        guard position.row >= 0, position.row < tableView.numberOfRows,
            position.tag >= 1, position.tag < tableView.numberOfColumns,
            let cell = tableView.view(atColumn: position.tag, row: position.row, makeIfNecessary: true),
            let field = cell.subviews.compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable })
        else { return }
        tableView.scrollRowToVisible(position.row)
        window?.makeFirstResponder(field)
    }

    /// Tab / ⇧Tab move to the next or previous cell instead of leaving the table.
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertTab(_:)) || selector == #selector(NSResponder.insertBacktab(_:)),
            let field = control as? NSTextField
        else { return false }
        let row = tableView.row(for: field), column = tableView.column(for: field)
        guard row >= 0, column >= 1 else { return false }
        let target = cell(
            after: CellPosition(row: row, tag: column),
            forward: selector == #selector(NSResponder.insertTab(_:)))
        window?.makeFirstResponder(tableView)  // commits, and the surface re-renders from the file
        if let target { beginEditingWhenReady(target) }
        return true
    }

    /// The edit lands when a data cell ends editing (↩ or focus out): nothing changes for the
    /// same value; otherwise the host rewrites that record's field in the buffer. A load that
    /// waited on the edit is applied first, and the edit is aimed at the record it was made on
    /// wherever the new file holds it.
    public func controlTextDidEndEditing(_ n: Notification) {
        guard let field = n.object as? NSTextField else { return }
        defer { replayPendingLoad() }
        let row = tableView.row(for: field), column = tableView.column(for: field)
        guard rows.indices.contains(row), column >= 1 else { return }
        let ci = column - 1
        let edited = rows[row], record = rowIndices[row]
        let old = edited.indices.contains(ci) ? edited[ci] : ""
        let typed = field.stringValue
        guard typed != old else { return }
        onEdit?(recordIndex(of: edited, near: record) + 1, ci, typed)
    }

    /// The data cell whose field editor holds the keyboard, or nil.
    private var editingField: NSTextField? {
        guard let editor = window?.firstResponder as? NSTextView, let field = editor.delegate as? NSTextField,
            field.isDescendant(of: tableView)
        else { return nil }
        return field
    }

    /// Applies the load an edit held back, a turn later: the end-editing notification arrives
    /// while the field editor still holds the keyboard, and a reload under it would lose the edit.
    private func replayPendingLoad() {
        guard pendingLoad != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let pending = self.pendingLoad, self.editingField == nil else { return }
            self.pendingLoad = nil
            self.apply(pending.csv, keepingFilter: pending.keepingFilter)
        }
    }

    /// The record `edited` is now, in the text a held-back load carries (else the shown one):
    /// `record` while that text still holds those values there, else the first record holding
    /// them (an outside insert above moved every row down), else `record`.
    private func recordIndex(of edited: [String], near record: Int) -> Int {
        let current = pendingLoad.map { Array(records(of: $0.csv).dropFirst()) } ?? allRows
        if current.indices.contains(record), current[record] == edited { return record }
        return current.firstIndex(of: edited) ?? record
    }

    /// The edit a cell would deliver on end-editing, for the harness: `row` indexes the SHOWN rows.
    public func commitEditForTesting(row: Int, column: Int, value: String) {
        guard rows.indices.contains(row) else { return }
        onEdit?(rowIndices[row] + 1, column, value)
    }
    /// The shown value at (row, column), for the harness.
    public func valueForTesting(row: Int, column: Int) -> String? {
        rows.indices.contains(row) && rows[row].indices.contains(column) ? rows[row][column] : nil
    }

    // MARK: - Table

    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    /// The theme's selection, not AppKit's accent blue: the cells keep their own colours on it.
    public func tableView(_ tv: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ThemedPlainRowView(accentBar: 0) }

    /// Builds/reuses a monospaced label cell. The "#" column shows the 1-based row number
    /// in muted status color; data columns index into the row by parsing the column id.
    public func tableView(_ tv: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let column, row < rows.count else { return nil }
        let id = column.identifier.rawValue
        let isIndex = (id == "#")
        let text: String
        if isIndex {
            text = "\(row + 1)"
        } else if let ci = Int(id.dropFirst()), ci < rows[row].count {
            text = rows[row][ci]
        } else {
            text = ""
        }

        // Two pools: the row counter stays a label, a data cell is an editable field (edits
        // go out through `controlTextDidEndEditing`). Each sits in a cell view pinned to the
        // row's vertical CENTRE (the .env table's recipe): handed the bare field, the table
        // stretches it to the row's full height and an editable field lays its text out from the
        // top, high in its band. `inkCentreForTesting` measures the pixels, not the frames.
        let cellId = NSUserInterfaceItemIdentifier(isIndex ? "csvindex" : "csvcell")
        let cell =
            tv.makeView(withIdentifier: cellId, owner: self) as? NSTableCellView
            ?? {
                let f = NSTextField.label("", font: cellFont, lineBreak: .byTruncatingTail)
                f.drawsBackground = false
                if !isIndex, !self.isReadOnly {
                    f.isEditable = true
                    f.isSelectable = true
                    f.isBezeled = false
                    f.focusRingType = .none
                    f.delegate = self
                    f.disableSystemTextIntelligence()
                }
                f.usesSingleLineMode = true
                f.cell?.usesSingleLineMode = true
                let c = NSTableCellView()
                c.identifier = cellId
                c.addSubviewsForAutoLayout(f)
                c.textField = f
                NSLayoutConstraint.activate([
                    f.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                    f.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -2),
                    f.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                ])
                return c
            }()
        cell.textField?.stringValue = text
        cell.textField?.textColor = isIndex ? Theme.statusText : Theme.foreground
        return cell
    }

    /// The vertical centre of the INK in `row` (the table's coordinates), against the row's own
    /// middle — rendered through `cacheDisplay`, so a field that draws its text high reads as
    /// high whatever its frame says. Nil when the row is empty or off screen.
    public func inkCentreForTesting(row: Int) -> (ink: CGFloat, middle: CGFloat)? {
        layoutSubtreeIfNeeded()
        tableView.layoutSubtreeIfNeeded()
        let rowRect = tableView.rect(ofRow: row)
        guard !rowRect.isEmpty, let rep = tableView.bitmapImageRepForCachingDisplay(in: rowRect) else { return nil }
        tableView.cacheDisplay(in: rowRect, to: rep)
        let scale = CGFloat(rep.pixelsWide) / rowRect.width
        let background = Theme.background.usingColorSpace(.sRGB) ?? Theme.background
        var minY = Int.max, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                // Ink is anything far from the page colour (the grid line is one pixel of near-page grey).
                if abs(c.redComponent - background.redComponent) + abs(c.greenComponent - background.greenComponent)
                    + abs(c.blueComponent - background.blueComponent) > 0.9
                {
                    minY = min(minY, y); maxY = max(maxY, y); break
                }
            }
        }
        guard maxY >= 0 else { return nil }
        // The bitmap's y runs from the rect's TOP in a flipped table; map back to points from the row's minY.
        let inkTop = rowRect.minY + CGFloat(minY) / scale, inkBottom = rowRect.minY + CGFloat(maxY + 1) / scale
        return ((inkTop + inkBottom) / 2, rowRect.midY)
    }

    /// Probe hooks for `--dump-csv-header`. Header-click sorting has no other headless view.
    public var probeTableView: NSTableView? { tableView }
    public var probeHeaders: [String] { headers }
    public func probeColumn(_ i: Int) -> [String] { rows.map { $0.indices.contains(i) ? $0[i] : "" } }

    /// Re-applies theme colors (background + grid) and reloads so cell text picks up the
    /// new foreground; called on light/dark switch.
    public func applyTheme() {
        layer?.backgroundColor = Theme.background.cgColor
        tableView.gridColor = Theme.rowSeparator
        tableView.headerView?.needsDisplay = true
        tableView.reloadData()
    }
}

// The header is `ThemedTableHeaderView` + `ThemedTableHeaderCell` from ThemedControls. Theming
// only the title is not enough: the stock cell paints its own system background, separator and
// bottom border over whatever the header view filled. The package's cell paints all of it from
// the palette and redraws the sort indicator a plain override would lose — every column here sorts.
