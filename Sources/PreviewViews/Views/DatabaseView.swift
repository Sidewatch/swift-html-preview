//
//  DatabaseView.swift
//  Sidewatch
//
//  SQLite browser + query runner, shown in the preview area for `.sqlite`/`.db` files.
//
//  Created by David Sherlock on 7/8/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import ThemedControls
import SQLiteReader
import UniformTypeIdentifiers
import FoundationExtensions
import AppKitViews

/// SQLite browser + query runner, shown in the preview area for `.sqlite`/`.db`
/// files. Left: tables. Right: a query editor + results grid. Zero-dependency.
///
/// The canonical table view (the grid a sidebar click produces) is *editable* for
/// ordinary rowid tables on a writable file: double-click a cell for an inline
/// edit (committed as a parameterized `UPDATE … WHERE rowid = ?`), "+ Row" inserts
/// a defaults/NULLs row. Views, `WITHOUT ROWID` tables, read-only files and custom
/// query results stay read-only (beep + "read-only" tooltip). The file is opened
/// read-only to browse and read-write on the first write.
public final class DatabaseView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    /// The open database: the file on disk, or an in-memory build of a schema file's DDL.
    public var db: SQLiteDB?
    /// Every table AND view, in the sidebar's order (`viewNames` says which are views).
    public var tables: [String] = []
    /// Rows per table, shown in the sidebar.
    public var tableCounts: [String: Int] = [:]
    /// What the grid shows now: a table's rows, a structure listing or a query's result.
    public var result = SQLiteDB.Result(columns: [], rows: [], error: nil, rowsAffected: 0)
    /// The last query's (or table's) rows, kept so switching back to Results restores them
    /// without re-running anything.
    public var lastQueryResult = SQLiteDB.Result(columns: [], rows: [], error: nil, rowsAffected: 0)
    /// The table picked in the sidebar or the diagram.
    public var currentTable: String?
    /// The file backing `db` (nil for in-memory schema.sql previews). Lets `load(_:)`
    /// recognize a re-render of the SAME database and refresh in place instead of
    /// rebuilding, and gates editing to real on-disk files.
    public var currentURL: URL?
    /// Whether the file behind `db` can be written: what makes a table editable, since the
    /// connection itself is read-only until the first write.
    public var fileIsWritable: Bool { currentURL.map { FileManager.default.isWritableFile(atPath: $0.path) } ?? false }
    /// Persistence key for the diagram's dragged box positions.
    public var diagramKey: String?
    /// The DDL text `loadSQL` last built `db` from — its counterpart to
    /// `currentURL`, so a re-render of the SAME schema refreshes in place instead
    /// of rebuilding (which would reset the mode and table selection).
    private var lastSQLText: String?

    // Cell editing (canonical table grid only)
    /// The table backing an editable grid — nil whenever the grid is read-only.
    public var editableTable: String?
    /// rowid per grid row, parallel to `result.rows` (canonical editable grid only).
    public var rowIDs: [Int64] = []
    /// True when the grid shows a table/view that *cannot* be edited (view,
    /// WITHOUT ROWID, read-only file) — drives the "read-only" tooltip.
    public var gridReadOnlyHint = false
    /// The in-flight inline edit (grid row/column + the pre-edit display value).
    public var editSession: (row: Int, col: Int, original: String)?
    /// A same-file reload arrived mid-edit; replayed when the edit session ends
    /// (the sidebar-rename deferral pattern — a reload would tear down the field).
    public var pendingRefresh = false
    /// Rows fetched into the canonical grid (matches the query the sidebar writes).
    public static let canonicalLimit = 200

    public let tableList = NSTableView()
    public let resultsTable = NSTableView()
    /// The results grid's own menu — Delete Row, built per click in `menuNeedsUpdate`.
    public let resultsMenu = NSMenu()
    /// Which of `tables` are VIEWS: the list holds both, and a view is not a table — it has no
    /// rowid, cannot be edited, and its count is of a query's rows.
    public var viewNames: Set<String> = []
    public let resultsScroll = ThemedScrollView()
    public let diagramScroll = ThemedScrollView()
    public let diagramView = SchemaDiagramView()
    public let queryView = QueryTextView()
    public let statusLabel = NSTextField(labelWithString: "")
    // The app's chrome (see CLAUDE.md): pills and a segment bar, never the system bezel.
    private let runButton = ThemedPillButton(
        title: String(localized: "Run  ⌘↩", bundle: .module, comment: "Database console button: run the query"))
    private let exportButton = ThemedPillButton(title: String(localized: "Export CSV", bundle: .module))
    public let addRowButton = ThemedPillButton(
        title: String(localized: "+ Row", bundle: .module, comment: "Database grid button: insert a new row"))
    /// The one inline editor, laid over the cell being edited.
    public let cellEditor = NSTextField()
    /// The empty state and the surface it is installed over, for the harness: "shown" is not
    /// "seen" if its host is hidden.
    public var emptyStateShownForTesting: Bool { !emptyState.isHidden }
    public var emptyStateHostHiddenForTesting: Bool { resultsScroll.isHiddenOrHasHiddenAncestor }
    public var diagramScrollForTesting: NSView { diagramScroll }

    /// Settable inside the view (a query lands on Results, a table pick keeps Structure); the
    /// host goes through `changeMode(to:)`, which commits any open cell edit first.
    public var mode: Mode = .results
    /// A browser without a console or edits: no query bar, no + Row, no cell editing (the Quick
    /// Look preview). Set before `load(_:)`.
    public var isReadOnly = false {
        didSet {
            queryContainer.isHidden = isReadOnly
            queryHeight?.constant = isReadOnly ? 0 : 96
            addRowButton.isHidden = isReadOnly
        }
    }
    /// The mode changed from inside (a query ran, a table was picked) — the host re-reads it for
    /// the breadcrumb's glyph.
    public var onModeChanged: (() -> Void)?

    /// Shows `mode` and tells the host. The one path in; `applyMode` does the work.
    public func setMode(_ new: Mode, notify: Bool = true) {
        mode = new
        applyMode()
        if notify { onModeChanged?() }
    }
    /// Reveals the surface `mode` names, without touching the stored value.
    public func applyMode() {
        switch mode {
        case .diagram: showDiagram()
        case .structure: showStructure()
        case .results: showResults()
        }
    }
    /// Width of the tables sidebar, dragged by the grip on its trailing edge and remembered
    /// across launches, so long table names have somewhere to go.
    private var sidebarWidth: NSLayoutConstraint?
    /// Narrowest useful sidebar, and how much room the results grid always keeps.
    private static let sidebarRange: ClosedRange<CGFloat> = 130...460
    private static let resultsMinWidth: CGFloat = 320

    /// Shown centered over the results grid when the DB can't be opened, or has no tables.
    public let emptyState = EmptyStateView(
        symbol: "exclamationmark.triangle", title: String(localized: "Couldn't Open Database", bundle: .module),
        subtitle: String(localized: "This file isn't a readable SQLite database.", bundle: .module))

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged),
            name: .themeDidChange, object: nil)
    }
    public required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    /// Applies a drag on the sidebar grip: `x` is the drag's position in this view, clamped so
    /// the sidebar stays usable and the results grid keeps `resultsMinWidth`. Written through
    /// to defaults on every drag rather than on mouse-up — there is no mouse-up to hook here
    /// (the grip reports positions only), and a width that survives the drag but not the
    /// session is worse than none.
    public func setSidebarWidth(_ x: CGFloat) {
        guard let sidebarWidth else { return }
        let ceiling = max(Self.sidebarRange.lowerBound, bounds.width - Self.resultsMinWidth)
        let width = min(x.clamped(to: Self.sidebarRange).rounded(), ceiling.rounded())
        guard width != sidebarWidth.constant else { return }
        sidebarWidth.constant = width
        PreviewViews.saveDatabaseSidebarWidth(width)
        layoutSubtreeIfNeeded()
    }

    /// The sidebar's current width — the harness reads it back after a simulated drag.
    public var sidebarWidthForTesting: CGFloat { sidebarWidth?.constant ?? 0 }

    /// Re-tints every surface whose colours were baked at build time. Without it the view keeps
    /// its birth theme: switch palettes and the query text can end up its old foreground on the
    /// new background — invisible, which reads as "the query box is gone".
    @objc private func themeChanged() {
        styleLayer(background: Theme.background)
        tableList.enclosingScrollView?.backgroundColor = Theme.sidebarBg
        tableList.backgroundColor = Theme.sidebarBg
        queryView.font = Theme.editorFont
        queryView.textColor = Theme.foreground
        queryView.backgroundColor = Theme.background
        queryView.insertionPointColor = Theme.cursor
        if let storage = queryView.textStorage {
            storage.addAttribute(
                .foregroundColor, value: Theme.foreground,
                range: storage.fullRange)
        }
        (queryView.enclosingScrollView as? ThemedScrollView)?.backgroundColor = Theme.background
        resultsScroll.backgroundColor = Theme.background
        resultsTable.backgroundColor = Theme.background
        diagramScroll.backgroundColor = Theme.background
        cellEditor.textColor = Theme.foreground
        cellEditor.backgroundColor = Theme.background
        statusLabel.font = Theme.uiFontSmall
        statusLabel.textColor = Theme.statusText
        // Header titles and sidebar cells bake their colors at build — rebuild both.
        rebuildResultColumns()
        resultsTable.reloadData()
        tableList.reloadData()
    }

    /// Open a `.sqlite`/`.db` file on disk, list its tables (with row counts), and
    /// auto-select the first so the preview shows data immediately.
    ///
    /// Re-rendering the SAME file (the preview re-renders on every status tick, and
    /// the file watcher fires after our own cell edits hit the disk) refreshes in
    /// place — selection, query text and any in-flight cell edit survive.
    public func load(_ url: URL) {
        let stamp = Self.fileStamp(url)
        if url == currentURL, db != nil {
            // A tab switch back to an unchanged file shows what is already built: re-counting every
            // table and rebuilding the grid cost ~20 ms per switch for nothing. A write (ours or
            // another process's) changes the file or its WAL, and refreshes.
            guard stamp != loadedFileStamp else { return }
            loadedFileStamp = stamp
            refreshInPlace()
            return
        }
        loadedFileStamp = stamp
        endCellEdit(commit: false)
        currentURL = url
        diagramKey = url.path
        lastSQLText = nil  // `db` is no longer loadSQL's — never let its guard match
        pendingRefresh = false
        currentTable = nil
        clearEditableGrid()
        // Browsing never opens for writing: a read-write connection to a WAL database creates `-wal` /
        // `-shm` beside the user's file. The first write (a cell edit, + Row, Delete Row, a typed
        // statement that writes) reopens read-write through `ensureWritable()`.
        db = SQLiteDB.openForReading(url)
        tables = db?.tables() ?? []
        viewNames = Set(db?.viewNames() ?? [])
        tableCounts = [:]
        for t in tables { tableCounts[t] = db?.rowCount(t) ?? 0 }
        tableList.reloadData()
        if db == nil {
            setStatus(String(localized: "Couldn't open database", bundle: .module), error: true)
            emptyState.show(
                symbol: "exclamationmark.triangle", title: String(localized: "Couldn't Open Database", bundle: .module),
                subtitle: String(localized: "This file isn't a readable SQLite database.", bundle: .module))
        } else if let first = tables.first {
            tableList.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            selectTable(first)
            emptyState.hide()
        } else {
            setStatus(
                fileIsWritable && !isReadOnly
                    ? String(localized: "No tables · read-write", bundle: .module)
                    : String(localized: "No tables · read-only", bundle: .module),
                error: false)
            emptyState.show(
                symbol: "cylinder.split.1x2", title: String(localized: "No Tables", bundle: .module),
                subtitle: String(localized: "This database has no tables.", bundle: .module))
        }
    }

    /// The database's full DDL: every `CREATE …` statement in `sqlite_master`, ordered
    /// tables → indexes → views → triggers (then by name), separated by blank lines. Used
    /// by the preview's raw-SQL toggle — read-only, so it never touches the live `db`.
    /// Returns a friendly `--` comment when the file can't be opened or has no schema.
    public static func schemaSQL(of url: URL) -> String {
        guard let db = SQLiteDB(url: url, readOnly: true) else {
            return "-- "
                + String(
                    localized: "Couldn't open this database.", bundle: .module,
                    comment: "Shown as an SQL comment in place of a database's schema")
        }
        let r = db.execute(
            """
            SELECT sql FROM sqlite_master WHERE sql IS NOT NULL
            ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 \
                               WHEN 'view' THEN 2 ELSE 3 END, name
            """, limit: 10_000)
        let stmts = r.rows.compactMap { $0.first }.filter { !$0.trimmed.isEmpty }
        guard !stmts.isEmpty else {
            return "-- "
                + String(
                    localized: "This database has no schema (no tables, indexes, or views).", bundle: .module,
                    comment: "Shown as an SQL comment in place of a database's schema")
        }
        return stmts.map { $0.hasSuffix(";") ? $0 : $0 + ";" }.joined(separator: "\n\n") + "\n"
    }

    /// Whether the content came from a SCHEMA FILE rather than a database: a `models.py`, a
    /// `schema.rb`, a `schema.prisma` or a `schema.sql` built into an in-memory database purely
    /// to draw it. It has no rows, nothing to export and nothing to write back, so the query bar
    /// is hidden and only the views that say something about the STRUCTURE are offered.
    public private(set) var showsSchemaSource = false
    /// The query box and its buttons; hidden whole for a schema source.
    private var queryContainer = NSView()
    /// Its height, zeroed with it so the diagram takes the room.
    private var queryHeight: NSLayoutConstraint?

    /// Visualize DDL by building it into an in-memory database. `key` (e.g. the file's path)
    /// enables per-file persistence of dragged diagram positions; the in-memory database itself
    /// is never cell-editable.
    public func loadSQL(_ sql: String, key: String? = nil, schemaSource: Bool = false) {
        showsSchemaSource = schemaSource
        queryContainer.isHidden = schemaSource
        queryHeight?.constant = schemaSource ? 0 : 96
        // Same schema re-rendered (theme change, tab switch back, background-tab
        // close): refresh in place, exactly like `load(_:)` does for a .db file.
        // Rebuilding would snap the user back to Diagram and drop their table
        // selection on events that are supposed to be non-destructive.
        if sql == lastSQLText, key == diagramKey, db != nil { refreshInPlace(); return }
        endCellEdit(commit: false)
        currentURL = nil
        diagramKey = key
        lastSQLText = sql
        pendingRefresh = false
        currentTable = nil
        clearEditableGrid()
        db = SQLiteDB(sql: sql)
        tables = db?.tables() ?? []
        tableList.reloadData()
        guard db != nil, !tables.isEmpty else {
            // Nothing to draw. Two things have to happen: the PREVIOUS file's boxes and rows go
            // (else another file's diagram shows under this file's name), and the state is shown
            // over a surface that is actually VISIBLE — it lives over the results scroll, which
            // the diagram may have hidden, and "shown" is not "seen".
            diagramView.clear()
            result = SQLiteDB.Result(columns: [], rows: [], error: nil, rowsAffected: 0)
            lastQueryResult = result
            rebuildResultColumns()
            resultsTable.reloadData()
            diagramScroll.isHidden = true
            resultsScroll.isHidden = false
            mode = .results
            setStatus(String(localized: "No CREATE TABLE statements found in this file", bundle: .module), error: db == nil)
            if db == nil {
                emptyState.show(
                    symbol: "exclamationmark.triangle", title: String(localized: "Couldn't Open Database", bundle: .module),
                    subtitle: String(localized: "This file isn't a readable SQLite database.", bundle: .module))
            } else {
                // Honest either way: the file may hold none, or hold some in a dialect SQLite
                // cannot read — a MySQL `CREATE TABLE \`orders\` … ENGINE=InnoDB` is skipped.
                emptyState.show(
                    symbol: "cylinder.split.1x2", title: String(localized: "No Tables", bundle: .module),
                    subtitle: String(localized: "No CREATE TABLE statement in this file could be read.", bundle: .module))
            }
            return
        }
        emptyState.hide()
        currentTable = tables.first
        mode = .diagram  // schema files have no rows — lead with the diagram
        showDiagram()
    }

    /// The loaded file's modification dates and sizes, its WAL's included.
    private var loadedFileStamp: String?

    /// `url`'s and its `-wal` file's modification date and size: what a write to the database changes.
    public static func fileStamp(_ url: URL) -> String {
        [url, URL(fileURLWithPath: url.path + "-wal")].map { file in
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return "\(values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0):\(values?.fileSize ?? -1)"
        }.joined(separator: "|")
    }

    /// Same-file re-render (watcher tick after an external/our-own write, theme or
    /// status refresh): re-read tables + counts and refresh the visible surface
    /// WITHOUT resetting the browser. Deferred while a cell edit is in flight —
    /// replayed by `endCellEdit` — so a reload never tears down the field mid-typing.
    /// Custom query results are never silently re-run (the box may hold a write).
    public func refreshInPlace() {
        guard db != nil else { return }
        if editSession != nil { pendingRefresh = true; return }
        tables = db?.tables() ?? []
        tableCounts = tableCounts.filter { tables.contains($0.key) }
        for t in tables { tableCounts[t] = db?.rowCount(t) ?? 0 }
        tableList.reloadData()
        if let sel = currentTable, let idx = tables.firstIndex(of: sel) {
            tableList.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        }
        switch mode {
        case .diagram: showDiagram()
        case .structure: showStructure()
        case .results:
            // Only the canonical table view re-reads its data (it's our own plain
            // SELECT — safe); a custom query result stays as cached — never re-run
            // user SQL here (the box may hold a write).
            if let t = currentTable, tables.contains(t), editableTable == t || gridReadOnlyHint {
                runCanonicalQuery(for: t)
            }
            showResults()
        }
    }

    /// Drops all editable-grid state (fresh load, custom query, non-table grid).
    public func clearEditableGrid() {
        editableTable = nil
        rowIDs = []
        gridReadOnlyHint = false
    }

    // MARK: - UI

    /// Assemble the whole view tree: left table list, right query editor + Run/Export
    /// controls, results grid and schema diagram (overlaid, picked by `mode`).
    private func buildUI() {
        styleLayer(background: Theme.background)

        // Left — table list
        let leftScroll = ThemedScrollView()
        leftScroll.hasVerticalScroller = true
        leftScroll.drawsBackground = true
        leftScroll.backgroundColor = Theme.sidebarBg
        tableList.headerView = nil
        tableList.backgroundColor = Theme.sidebarBg
        tableList.rowHeight = 26
        tableList.gridStyleMask = []
        let tcol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("t"))
        tableList.addTableColumn(tcol)
        tableList.dataSource = self
        tableList.delegate = self
        tableList.target = self
        tableList.action = #selector(tableClicked)
        leftScroll.documentView = tableList

        // Right — query editor
        let queryScroll = ThemedScrollView()
        queryScroll.hasVerticalScroller = true
        queryScroll.borderType = .noBorder
        queryScroll.drawsBackground = true
        queryScroll.backgroundColor = Theme.background
        queryView.isRichText = false
        queryView.font = Theme.editorFont
        queryView.textColor = Theme.foreground
        queryView.backgroundColor = Theme.background
        queryView.insertionPointColor = Theme.cursor
        queryView.isAutomaticQuoteSubstitutionEnabled = false
        queryView.textContainerInset = NSSize(width: 6, height: 6)
        // The full bare-NSTextView-in-a-scroll-view recipe. A text view created with
        // `NSTextView()` keeps a zero frame and never tracks the scroll view's width —
        // the text exists but renders nowhere and clicks land on nothing, which reads
        // as "the query box is gone". Every line here is load-bearing.
        queryView.minSize = .zero
        queryView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
        queryView.isVerticallyResizable = true
        queryView.isHorizontallyResizable = false
        queryView.autoresizingMask = [.width]
        queryView.textContainer?.widthTracksTextView = true
        queryView.onRun = { [weak self] in self?.runQuery() }
        queryScroll.documentView = queryView

        runButton.target = self
        runButton.action = #selector(runQuery)

        exportButton.prominent = false
        exportButton.target = self
        exportButton.action = #selector(exportCSV)

        addRowButton.prominent = false
        addRowButton.target = self
        addRowButton.action = #selector(addRow)
        addRowButton.isEnabled = false  // enabled only for an editable canonical grid

        // Right — results grid
        resultsScroll.hasVerticalScroller = true
        resultsScroll.hasHorizontalScroller = true
        resultsScroll.drawsBackground = true
        resultsScroll.backgroundColor = Theme.background
        resultsTable.backgroundColor = Theme.background
        // NOT the system alternating colors — they ignore the app theme (light-grey bars
        // on the dark surface, and they tile the whole empty area when a table has 0 rows).
        // Themed zebra is applied per-row in `tableView(_:didAdd:forRow:)` instead.
        resultsTable.usesAlternatingRowBackgroundColors = false
        resultsTable.rowHeight = 22
        resultsTable.columnAutoresizingStyle = .noColumnAutoresizing
        resultsTable.dataSource = self
        resultsTable.delegate = self
        resultsTable.target = self
        resultsTable.doubleAction = #selector(cellDoubleClicked)
        resultsTable.allowsMultipleSelection = true
        // Delete lives on the row's menu, not on another pill.
        resultsTable.menu = resultsMenu
        resultsMenu.delegate = self
        resultsScroll.documentView = resultsTable

        // Inline cell editor: a single overlay field positioned over the edited cell
        // (added to the table view so it scrolls with the rows).
        cellEditor.font = NSFont.mono(11)
        cellEditor.disableSystemTextIntelligence()
        cellEditor.textColor = Theme.foreground
        cellEditor.backgroundColor = Theme.background
        cellEditor.drawsBackground = true
        cellEditor.isBordered = true
        cellEditor.delegate = self
        if let cell = cellEditor.cell as? NSTextFieldCell {
            cell.usesSingleLineMode = true
            cell.wraps = false
            cell.isScrollable = true
        }

        // Right — schema diagram (hidden until Diagram mode)
        diagramScroll.hasVerticalScroller = true
        diagramScroll.hasHorizontalScroller = true
        diagramScroll.drawsBackground = true
        diagramScroll.backgroundColor = Theme.background
        diagramScroll.documentView = diagramView
        diagramScroll.isHidden = true
        // Route a diagram click through the SAME path as a sidebar click. Setting
        // currentTable here directly would leave editableTable/rowIDs/lastQueryResult
        // pointing at the previously selected table — the grid would then look like
        // the new table while cell edits wrote UPDATEs against the old one.
        diagramView.onSelectTable = { [weak self] t in
            guard let self, let idx = self.tables.firstIndex(of: t) else { return }
            self.tableList.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            self.tableList.scrollRowToVisible(idx)
            self.mode = .structure  // selectTable preserves Structure mode
            self.selectTable(t)
        }

        statusLabel.font = Theme.uiFontSmall
        statusLabel.textColor = Theme.statusText

        queryContainer = NSView()
        queryContainer.addSubviewsForAutoLayout(queryScroll)
        queryContainer.addSubview(addRowButton)
        queryContainer.addSubview(exportButton)
        queryContainer.addSubview(runButton)

        let rightSplit = NSView()
        rightSplit.addSubviewsForAutoLayout(queryContainer, resultsScroll, diagramScroll, statusLabel)

        addSubviewsForAutoLayout(leftScroll, rightSplit)

        // The seam between the sidebar and the grid, as a 14pt drag target with a resize
        // cursor — the same grip the editor uses against its preview pane.
        let grip = PaneDividerGrip()
        addSubviewsForAutoLayout(grip)
        grip.onDrag = { [weak self] x in self?.setSidebarWidth(x) }

        let width = PreviewViews.savedDatabaseSidebarWidth().map { $0.clamped(to: Self.sidebarRange) } ?? 190
        let sidebar = leftScroll.widthAnchor.constraint(equalToConstant: width)
        sidebarWidth = sidebar

        NSLayoutConstraint.activate([
            leftScroll.topAnchor.constraint(equalTo: topAnchor),
            leftScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebar,

            grip.topAnchor.constraint(equalTo: topAnchor),
            grip.bottomAnchor.constraint(equalTo: bottomAnchor),
            grip.centerXAnchor.constraint(equalTo: leftScroll.trailingAnchor),
            grip.widthAnchor.constraint(equalToConstant: PaneDividerGrip.width),

            rightSplit.topAnchor.constraint(equalTo: topAnchor),
            rightSplit.leadingAnchor.constraint(equalTo: leftScroll.trailingAnchor, constant: 1),
            rightSplit.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightSplit.bottomAnchor.constraint(equalTo: bottomAnchor),

            queryContainer.topAnchor.constraint(equalTo: rightSplit.topAnchor),
            {
                let c = queryContainer.heightAnchor.constraint(equalToConstant: 96); queryHeight = c; return c
            }(),
            queryContainer.leadingAnchor.constraint(equalTo: rightSplit.leadingAnchor),
            queryContainer.trailingAnchor.constraint(equalTo: rightSplit.trailingAnchor),

            queryScroll.topAnchor.constraint(equalTo: queryContainer.topAnchor, constant: 8),
            queryScroll.leadingAnchor.constraint(equalTo: queryContainer.leadingAnchor, constant: 8),
            queryScroll.trailingAnchor.constraint(equalTo: queryContainer.trailingAnchor, constant: -8),
            queryScroll.bottomAnchor.constraint(equalTo: runButton.topAnchor, constant: -6),

            runButton.trailingAnchor.constraint(equalTo: queryContainer.trailingAnchor, constant: -8),
            runButton.bottomAnchor.constraint(equalTo: queryContainer.bottomAnchor, constant: -6),

            exportButton.trailingAnchor.constraint(equalTo: runButton.leadingAnchor, constant: -8),
            exportButton.centerYAnchor.constraint(equalTo: runButton.centerYAnchor),

            addRowButton.trailingAnchor.constraint(equalTo: exportButton.leadingAnchor, constant: -8),
            addRowButton.centerYAnchor.constraint(equalTo: runButton.centerYAnchor),

            resultsScroll.topAnchor.constraint(equalTo: queryContainer.bottomAnchor),
            resultsScroll.leadingAnchor.constraint(equalTo: rightSplit.leadingAnchor),
            resultsScroll.trailingAnchor.constraint(equalTo: rightSplit.trailingAnchor),
            resultsScroll.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -4),

            diagramScroll.topAnchor.constraint(equalTo: queryContainer.bottomAnchor),
            diagramScroll.leadingAnchor.constraint(equalTo: rightSplit.leadingAnchor),
            diagramScroll.trailingAnchor.constraint(equalTo: rightSplit.trailingAnchor),
            diagramScroll.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -4),

            statusLabel.leadingAnchor.constraint(equalTo: rightSplit.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: rightSplit.trailingAnchor, constant: -10),
            statusLabel.bottomAnchor.constraint(equalTo: rightSplit.bottomAnchor, constant: -6),
            statusLabel.heightAnchor.constraint(equalToConstant: 16),
        ])

        emptyState.install(over: resultsScroll)
    }

}
