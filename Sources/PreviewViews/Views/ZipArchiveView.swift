//
//  ZipArchiveView.swift
//  Sidewatch
//
//  Read-only preview of an archive's contents *without* unpacking it: swift-archive-index reads
//  the zip's central directory (or the tar's headers), so the structure shows as a tree instantly.
//
//  Created by David Sherlock on 7/18/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import ThemedControls
import ArchiveIndex
import AppKitViews
import FoundationExtensions

/// Read-only preview of an archive's contents *without* unpacking it: `Archive.listing(at:)`
/// (swift-archive-index) reads a zip's central directory or a tar's headers, so the structure
/// shows as a tree instantly. Double-click a file to pull just that member out
/// (`Archive.data(for:kind:in:)`: stored or DEFLATE) into a temp file and open it in a tab.
public final class ZipArchiveView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, ExpandableTree {
    /// How many rows a freshly-listed archive may open to on its own.
    public static let autoExpandRowLimit = 400

    /// Opens an extracted entry (a temp file) through the normal open-file path.
    public var onOpenFile: ((URL) -> Void)?

    private let summary = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let outline = NSOutlineView()
    private let scroll = ThemedScrollView()
    private var roots: [ArchiveNode] = []
    private var listing: ArchiveListing?
    private var loadedURL: URL?
    /// The summary the listing earned — restored after an extraction's progress line.
    private var listingSummary = ""
    /// Each member's modified date, by path without a folder's trailing slash.
    private var modified: [String: Date] = [:]
    private static let nameColumn = NSUserInterfaceItemIdentifier("entry")
    private static let sizeColumn = NSUserInterfaceItemIdentifier("size")
    private static let dateColumn = NSUserInterfaceItemIdentifier("modified")
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Layout

    private func build() {
        summary.font = Theme.uiFontSmall
        summary.textColor = Theme.statusText
        summary.lineBreakMode = .byTruncatingTail
        addSubviewsForAutoLayout(summary)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        addSubviewsForAutoLayout(spinner)

        // Name, Size and Modified under a themed header, the name taking the spare width: what a
        // reviewer wants from an archive at a glance (and all Quick Look can offer — there is no
        // tab to open a member in).
        outline.headerView = ThemedTableHeaderView()
        outline.rowHeight = 22
        outline.backgroundColor = .clear
        outline.indentationPerLevel = 14
        outline.selectionHighlightStyle = .regular
        outline.autoresizesOutlineColumn = false
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        for (id, title, width) in [
            (Self.nameColumn, String(localized: "Name", bundle: .module, comment: "Archive tree column: member names"), CGFloat(360)),
            (Self.sizeColumn, String(localized: "Size", bundle: .module, comment: "Archive tree column: unpacked sizes"), 90),
            (
                Self.dateColumn, String(localized: "Modified", bundle: .module, comment: "Archive tree column: when each member changed"),
                170
            ),
        ] {
            let col = NSTableColumn(identifier: id)
            col.isEditable = false
            col.headerCell = ThemedTableHeaderCell(title: title, titleInset: 6)
            col.width = width
            col.minWidth = id == Self.nameColumn ? 160 : 60
            outline.addTableColumn(col)
        }
        outline.outlineTableColumn = outline.tableColumns.first
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(rowDoubleClicked)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = outline
        addSubviewsForAutoLayout(scroll)

        // The same pair the structure tree offers: on a folder they mean that
        // folder and everything under it, on a file or empty space the whole archive.
        let menu = NSMenu()
        for (title, sel, symbol) in [
            (String(localized: "Expand All", bundle: .module), #selector(expandAllClicked), "arrow.down.right.and.arrow.up.left.rectangle"),
            (
                String(localized: "Collapse All", bundle: .module), #selector(collapseAllClicked),
                "arrow.up.left.and.arrow.down.right.rectangle"
            ),
        ] {
            menu.addItem(title, action: sel, target: self, symbol: symbol)
        }
        outline.menu = menu

        NSLayoutConstraint.activate([
            summary.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            summary.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            summary.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            spinner.centerYAnchor.constraint(equalTo: summary.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyTheme()
    }

    @objc private func themeChanged() { applyTheme(); outline.reloadData() }
    private func applyTheme() {
        layer?.backgroundColor = Theme.sidebarBg.cgColor
        summary.textColor = Theme.statusText
        outline.backgroundColor = Theme.sidebarBg
    }

    // MARK: - Load

    /// Lists the archive's entries (off-main) and builds the tree. Cheap re-render
    /// calls with the same URL are ignored so the listing runs once per open.
    public func load(url: URL) {
        guard url != loadedURL else { return }
        loadedURL = url
        roots = []; listing = nil; modified = [:]; listingSummary = ""
        outline.reloadData()
        summary.stringValue = String(localized: "Reading archive…", bundle: .module)
        spinner.startAnimation(nil)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let listing = try? Archive.listing(at: url)
            let tree = listing?.tree ?? []
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadedURL == url else { return }
                self.spinner.stopAnimation(nil)
                self.roots = tree
                self.listing = listing
                self.modified = Dictionary(
                    (listing?.entries ?? []).compactMap { e in e.modified.map { (Self.trimmed(e.path), $0) } },
                    uniquingKeysWith: { a, _ in a })
                self.listingSummary = listing.map(Self.summary) ?? ""
                self.summary.stringValue =
                    self.listingSummary.isEmpty
                    ? String(localized: "Couldn't read this archive (or it's empty).", bundle: .module) : self.listingSummary
                self.outline.reloadData()
                // Open as much of the archive as stays readable — a small one lands whole, a
                // big one at the depth that fits (Expand All opens the rest).
                self.outline.autoExpand(rowLimit: ZipArchiveView.autoExpandRowLimit)
            }
        }
    }

    // MARK: - Extract + open

    @objc private func rowDoubleClicked() {
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? ArchiveNode else { return }
        if node.isDirectory { outline.isItemExpanded(node) ? outline.collapseItem(node) : outline.expandItem(node); return }
        // Nowhere to open a member (the Quick Look preview): a double-click on a file does nothing.
        guard onOpenFile != nil, let zip = loadedURL, let listing, let entry = listing.entries.first(where: { $0.path == node.path }) else {
            return
        }
        extractAndOpen(entry: entry, kind: listing.kind, from: zip)
    }

    /// Unpacks one member into a temp file (basename preserved so its extension drives the
    /// preview) and opens it. Off-main; opens on main. A member packed with a method the package
    /// does not unpack (bzip2, LZMA) or an encrypted one beeps.
    private func extractAndOpen(entry: ArchiveEntry, kind: ArchiveKind, from zip: URL) {
        summary.stringValue = String(
            localized: "Extracting \(entry.name)…", bundle: .module, comment: "Archive preview status; the placeholder is a file name")
        spinner.startAnimation(nil)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = try? Archive.data(for: entry, kind: kind, in: zip)
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("Sidewatch-archive/\(zip.deletingPathExtension().lastPathComponent)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(entry.name)
            let ok = (data != nil) && ((try? data!.write(to: dest)) != nil)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.spinner.stopAnimation(nil)
                self.restoreSummary()
                if ok { self.onOpenFile?(dest) } else { NSSound.beep() }
            }
        }
    }

    /// Puts the listing's summary back after an extraction's progress line.
    private func restoreSummary() { summary.stringValue = listingSummary }

    /// "Zip · 7 files · 5 folders · 12 KB uncompressed · 4.1 KB compressed (34%)" — the
    /// compressed part only for a zip, where it differs.
    static func summary(of listing: ArchiveListing) -> String {
        guard !listing.entries.isEmpty else { return "" }
        let files = listing.fileCount, folders = listing.folderCount
        var parts = [
            listing.kind == .zip ? "Zip" : "Tar",
            String(localized: "\(files) files", bundle: .module, comment: "Archive summary: how many files the archive holds"),
        ]
        if folders > 0 {
            parts.append(String(localized: "\(folders) folders", bundle: .module, comment: "Archive summary: how many folders"))
        }
        let total = listing.totalSize
        parts.append(
            String(
                localized: "\(total.byteSizeLabel) uncompressed", bundle: .module,
                comment: "Archive summary: the total size once extracted, e.g. 12 KB uncompressed"))
        let packed = listing.entries.reduce(0) { $0 + ($1.isDirectory ? 0 : $1.compressedSize) }
        if listing.kind == .zip, total > 0 {
            // Never "0%" for a member that takes bytes: a highly compressible archive reads 1%.
            let percent = max(packed > 0 ? 1 : 0, Int((Double(packed) / Double(total) * 100).rounded()))
            parts.append(
                String(
                    localized: "\(packed.byteSizeLabel) compressed (\(percent)%)", bundle: .module,
                    comment: "Archive summary: the bytes the archive spends, and that as a share of the uncompressed size"))
        }
        return parts.joined(separator: " · ")
    }

    /// A member's path without the trailing slash a folder entry carries.
    private static func trimmed(_ path: String) -> String { path.hasSuffix("/") ? String(path.dropLast()) : path }

    /// The summary line as shown, for the harness.
    public var summaryForTesting: String { summary.stringValue }

    // MARK: - Expand / collapse

    /// Opens every folder, however deep — View ▸ Expand All while the archive is on screen.
    public func expandAllNodes() { outline.expandEveryNode() }
    /// Closes every folder.
    public func collapseAllNodes() { outline.collapseEveryNode() }

    @objc private func expandAllClicked() {
        guard let node = clickedFolder() else { return expandAllNodes() }
        outline.expandItem(node, expandChildren: true)
    }
    @objc private func collapseAllClicked() {
        guard let node = clickedFolder() else { return collapseAllNodes() }
        outline.collapseItem(node, collapseChildren: true)
    }
    private func clickedFolder() -> ArchiveNode? {
        guard outline.clickedRow >= 0, let node = outline.item(atRow: outline.clickedRow) as? ArchiveNode,
            node.isDirectory
        else { return nil }
        return node
    }
    /// Every row the outline currently shows, for the harness.
    public var visibleRowCountForTesting: Int { outline.numberOfRows }
    /// The context menu's titles, for the harness.
    public var menuTitlesForTesting: [String] { outline.menu?.items.map(\.title).filter { !$0.isEmpty } ?? [] }

    // MARK: - Outline data source / delegate

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? ArchiveNode)?.children.count ?? roots.count
    }
    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? ArchiveNode)?.children[index] ?? roots[index]
    }
    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? ArchiveNode)?.isDirectory ?? false
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? ArchiveNode else { return nil }
        let cell = NSTableCellView()
        switch tableColumn?.identifier {
        case Self.sizeColumn?, Self.dateColumn?:
            let text =
                tableColumn?.identifier == Self.sizeColumn
                ? node.size.byteSizeLabel
                : modified[Self.trimmed(node.path)].map { Self.dateFormatter.string(from: $0) } ?? ""
            let label = NSTextField.label(
                text, font: Theme.uiFontSmall, color: Theme.statusText,
                alignment: tableColumn?.identifier == Self.sizeColumn ? .right : .left)
            label.lineBreakMode = .byTruncatingTail
            cell.addSubviewsForAutoLayout(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        default:
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: node.isDirectory ? "folder" : "doc", accessibilityDescription: nil)
            icon.contentTintColor = node.isDirectory ? Theme.accent : Theme.sidebarText.withAlphaComponent(0.7)
            icon.imageScaling = .scaleProportionallyDown
            let name = NSTextField.label(
                node.name, font: .systemFont(ofSize: 12, weight: node.isDirectory ? .medium : .regular), color: Theme.sidebarText,
                lineBreak: .byTruncatingMiddle)
            cell.addSubviewsForAutoLayout(icon, name)
            cell.textField = name
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 14),
                icon.heightAnchor.constraint(equalToConstant: 14),
                name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                name.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            ])
            return cell
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { ThemedPlainRowView(accentBar: 0) }
}
