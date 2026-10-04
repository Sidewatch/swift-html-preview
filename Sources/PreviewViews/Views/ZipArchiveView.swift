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

        outline.headerView = nil
        outline.rowHeight = 22
        outline.backgroundColor = .clear
        outline.indentationPerLevel = 14
        outline.selectionHighlightStyle = .regular
        outline.autoresizesOutlineColumn = false
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
        col.isEditable = false
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
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
        roots = []; listing = nil
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
                if let listing, !listing.entries.isEmpty {
                    let dirCount = listing.folderCount, fileCount = listing.fileCount
                    let size = listing.totalSize.byteSizeLabel
                    self.summary.stringValue =
                        dirCount > 0
                        ? String(
                            localized: "\(fileCount) files · \(dirCount) folders · \(size) uncompressed", bundle: .module,
                            comment: "Archive preview summary: file count, folder count, total uncompressed size")
                        : String(
                            localized: "\(fileCount) files · \(size) uncompressed", bundle: .module,
                            comment: "Archive preview summary: file count, total uncompressed size")
                } else {
                    self.summary.stringValue = String(localized: "Couldn't read this archive (or it's empty).", bundle: .module)
                }
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
        guard let zip = loadedURL, let listing, let entry = listing.entries.first(where: { $0.path == node.path }) else { return }
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

    /// Rebuilds the summary line after an extraction (reuses the cached tree).
    private func restoreSummary() {
        let files = countFiles(roots)
        summary.stringValue = String(localized: "\(files) files — double-click to preview", bundle: .module)
    }
    private func countFiles(_ nodes: [ArchiveNode]) -> Int { nodes.reduce(0) { $0 + $1.fileCount } }

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

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: node.isDirectory ? "folder" : "doc", accessibilityDescription: nil)
        icon.contentTintColor = node.isDirectory ? Theme.accent : Theme.sidebarText.withAlphaComponent(0.7)
        icon.imageScaling = .scaleProportionallyDown

        let name = NSTextField.label(node.name, font: .systemFont(ofSize: 12), color: Theme.sidebarText, lineBreak: .byTruncatingMiddle)

        let size = NSTextField.label(
            node.isDirectory ? "" : node.size.byteSizeLabel, font: Theme.uiFontSmall, color: Theme.statusText, alignment: .right)
        size.setContentCompressionResistancePriority(.required, for: .horizontal)
        size.setContentHuggingPriority(.required, for: .horizontal)

        cell.addSubviewsForAutoLayout(icon, name, size)
        cell.textField = name
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: size.leadingAnchor, constant: -6),
            size.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            size.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    public func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { ThemedPlainRowView(accentBar: 0) }
}
