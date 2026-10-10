//
//  JSONTreeView.swift
//  Sidewatch
//
//  A collapsible tree view of a JSON document (DevKnife-style) — keys, typed + colored values,
//  expand/collapse.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import ThemedControls
import AppKitViews
import DataConverter

/// A collapsible tree view of a structured document — JSON, YAML, TOML, XML, property lists,
/// INI, .properties and .strings — keys, typed + coloured values, expand/collapse, keys and
/// values edited in place, and the find bar as a filter.
public final class JSONTreeView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSMenuDelegate,
    PreviewFindable,
    ExpandableTree,
    CellTabbing
{
    /// How many rows a freshly-loaded tree may open to on its own. A config file
    /// is almost always well under it and lands fully open; a big document opens to the depth
    /// that fits and the rest is one click, or Expand All, away.
    public static let autoExpandRowLimit = 400

    /// A key or value edited in a cell (double-click): the node, which half, the typed text. The
    /// host rewrites the one token in the buffer (`TreeFormat.replacement`) and the tree
    /// re-renders from it.
    public var onEdit: ((JSONItem, EditTarget, String) -> Void)?
    /// Shows without editing: keys and values stay labels (the Quick Look preview).
    public var isReadOnly = false
    private let outline = RecyclingOutlineView()
    private let scroll = ThemedScrollView()
    /// Shown centered over the tree when the JSON is invalid, or an empty container.
    private let emptyState = EmptyStateView(
        symbol: "exclamationmark.triangle", title: String(localized: "Invalid JSON", bundle: .module),
        subtitle: String(localized: "This file isn't valid JSON.", bundle: .module))
    private var root: [JSONItem] = []
    /// The document as a value, file order kept, for the copy-as-JSON/YAML items; nil when unreadable.
    private var rootValue: StructuredValue?
    /// The row the context menu was opened on (-1: empty space) — the items act on it.
    private var menuRow = -1
    /// A load that arrived while a cell was being edited, applied once the edit ends: `reloadData`
    /// under an open field editor ends the edit with the typed text lost.
    private var pendingLoad: (() -> Void)?
    /// Whether a load is waiting for an edit to end, for the harness.
    public var hasPendingLoadForTesting: Bool { pendingLoad != nil }

    // MARK: Find-bar filter state
    /// The query the tree is filtered by, and its case rule; empty means the whole tree.
    private var query = ""
    private var queryCaseSensitive = false
    /// The nodes shown while filtering — every match and every ancestor of one — or nil when
    /// the whole tree shows. Identity-keyed: the nodes are the same objects across reloads,
    /// which is also what keeps the expansion state.
    private var visible: Set<ObjectIdentifier>?
    /// The matching nodes in outline order, for the count and ▲ ▼.
    private var matched: [JSONItem] = []
    /// What was expanded before the filter, put back when it clears.
    private var expansionBeforeFilter: Set<ObjectIdentifier>?

    public override init(frame frameRect: NSRect) { super.init(frame: frameRect); build() }
    public required init?(coder: NSCoder) { fatalError() }

    /// Wires up the outline view, scroll host, right-click Copy Path/Value menu,
    /// and the centered empty/invalid-JSON state; all pinned via Auto Layout.
    private func build() {
        styleLayer(background: Theme.background)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        outline.backgroundColor = .clear
        outline.headerView = nil
        outline.rowHeight = 22
        outline.indentationPerLevel = 14
        outline.autoresizesOutlineColumn = false
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("json"))
        col.resizingMask = .autoresizingMask
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.dataSource = self
        outline.delegate = self
        scroll.documentView = outline
        addSubviewsForAutoLayout(scroll)

        // Built each time it opens: a row's own items on a row, the whole document's on empty space.
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu

        scroll.pinEdges(to: self)

        emptyState.install(over: scroll)

        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
    }

    /// Repaints for a theme flip WITHOUT rebuilding the items — `reloadData` over the
    /// same node objects keeps the user's expanded state, and the cells re-read the
    /// live `Theme`-derived colors.
    @objc private func themeChanged() {
        layer?.backgroundColor = Theme.background.cgColor
        outline.reloadData()
    }

    /// Parses `jsonText` (fragments allowed; comments, trailing commas and JSON5 keys too when
    /// `lenient`) into the tree, keys sorted, and reloads, opening it as far as `autoExpandRowLimit` allows. Shows a centred "Invalid JSON" state (and clears
    /// the tree) on parse failure, or "Empty JSON" for an empty container.
    public func load(_ jsonText: String, lenient: Bool = false, keepingExpansion: Bool = false) {
        if editingField != nil {
            pendingLoad = { [weak self] in self?.applyJSON(jsonText, lenient: lenient, keepingExpansion: keepingExpansion) }
            return
        }
        pendingLoad = nil
        applyJSON(jsonText, lenient: lenient, keepingExpansion: keepingExpansion)
    }

    /// The JSON load itself, once no field editor is open over the tree.
    private func applyJSON(_ jsonText: String, lenient: Bool, keepingExpansion: Bool) {
        let expanded = keepingExpansion ? expandedPaths() : []
        guard let obj = TreeFormat.jsonObject(jsonText, lenient: lenient) else {
            root = []; rootValue = nil; outline.reloadData()
            emptyState.show(
                symbol: "exclamationmark.triangle", title: String(localized: "Invalid JSON", bundle: .module),
                subtitle: String(localized: "This file isn't valid JSON.", bundle: .module))
            return
        }
        rootValue = JSONStructure.value(of: jsonText) ?? Self.structuredValue(obj)
        if let dict = obj as? [String: Any] {
            root = dict.keys.sorted().map {
                JSONItem(label: $0, value: dict[$0] ?? NSNull(), path: "$".jsonPathAppending(key: $0), components: [.key($0)])
            }
        } else if let arr = obj as? [Any] {
            root = arr.enumerated().map {
                JSONItem(label: "[\($0.offset)]", value: $0.element, path: "$[\($0.offset)]", components: [.index($0.offset)])
            }
        } else {
            root = [JSONItem(label: "value", value: obj, path: "$")]
        }
        outline.reloadData()
        outline.autoExpand(rowLimit: Self.autoExpandRowLimit)
        restoreExpansion(expanded)
        if root.isEmpty {
            emptyState.show(
                symbol: "curlybraces", title: String(localized: "Empty JSON", bundle: .module),
                subtitle: String(localized: "No values to show.", bundle: .module))
        } else {
            emptyState.hide()
        }
    }

    /// A structured document other than JSON: the same tree, keys in file order, from a package
    /// reader's value. Nil (an empty or unreadable document) shows
    /// the empty state named for the format; a malformed file shows whatever structure the
    /// reader could see. `renamesKey` is the format's rule for which keys a cell may rename.
    public func load(
        structured value: StructuredValue?, format: String, keepingExpansion: Bool = false,
        renamesKey: @escaping (String) -> Bool = { _ in true }
    ) {
        if editingField != nil {
            pendingLoad = { [weak self] in
                self?.applyStructured(value, format: format, keepingExpansion: keepingExpansion, renamesKey: renamesKey)
            }
            return
        }
        pendingLoad = nil
        applyStructured(value, format: format, keepingExpansion: keepingExpansion, renamesKey: renamesKey)
    }

    /// The structured load itself, once no field editor is open over the tree.
    private func applyStructured(
        _ value: StructuredValue?, format: String, keepingExpansion: Bool, renamesKey: @escaping (String) -> Bool
    ) {
        let expanded = keepingExpansion ? expandedPaths() : []
        guard let value else {
            root = []; rootValue = nil; outline.reloadData()
            emptyState.show(
                symbol: "doc.text",
                title: String(
                    localized: "Empty \(format)", bundle: .module,
                    comment: "Structure tree empty state; the placeholder is a format name such as YAML or TOML"),
                subtitle: String(localized: "No values to show.", bundle: .module))
            return
        }
        rootValue = value
        switch value {
        case .mapping(let pairs):
            root = pairs.map {
                JSONItem(
                    label: $0.key, value: $0.value, path: "$".jsonPathAppending(key: $0.key), components: [.key($0.key)],
                    renamesKey: renamesKey)
            }
        case .sequence(let items):
            root = items.enumerated().map {
                JSONItem(
                    label: "[\($0.offset)]", value: $0.element, path: "$[\($0.offset)]", components: [.index($0.offset)],
                    renamesKey: renamesKey)
            }
        default: root = [JSONItem(label: "value", value: value, path: "$", renamesKey: renamesKey)]
        }
        outline.reloadData()
        outline.autoExpand(rowLimit: Self.autoExpandRowLimit)
        restoreExpansion(expanded)
        if root.isEmpty {
            emptyState.show(
                symbol: "doc.text",
                title: String(
                    localized: "Empty \(format)", bundle: .module,
                    comment: "Structure tree empty state; the placeholder is a format name such as YAML or TOML"),
                subtitle: String(localized: "No values to show.", bundle: .module))
        } else {
            emptyState.hide()
        }
    }

    /// The paths expanded now — what an edit's re-render must keep (the nodes are rebuilt).
    private func expandedPaths() -> Set<String> { Set(allItems().filter { outline.isItemExpanded($0) }.map(\.path)) }
    private func restoreExpansion(_ paths: Set<String>) {
        guard !paths.isEmpty else { return }
        for item in allItems() where paths.contains(item.path) { outline.expandItem(item) }
    }

    // MARK: - Editing

    // MARK: - Tab between cells

    /// Every cell the tree will open, in reading order: each visible row's key then its value.
    public var editableCells: [CellPosition] {
        (0..<outline.numberOfRows).flatMap { row -> [CellPosition] in
            guard let node = outline.item(atRow: row) as? JSONItem else { return [] }
            return [
                node.keyIsEditable ? CellPosition(row: row, tag: 1) : nil,
                node.valueIsEditable ? CellPosition(row: row, tag: 2) : nil,
            ].compactMap { $0 }
        }
    }

    /// Which cell holds the keyboard now, as "path/key" or "path/value", for the harness.
    public var editingCellPathForTesting: String? {
        guard let editor = window?.firstResponder as? NSTextView, let field = editor.delegate as? NSTextField,
            field.isDescendant(of: self)
        else { return nil }
        let row = outline.row(for: field)
        guard let node = outline.item(atRow: row) as? JSONItem else { return nil }
        return node.path + (field.tag == 1 ? "/key" : "/value")
    }

    /// Opens a cell for editing — used by Tab, and by the harness.
    public func beginEditing(_ position: CellPosition) {
        guard position.row >= 0, position.row < outline.numberOfRows,
            let cell = outline.view(atColumn: 0, row: position.row, makeIfNecessary: true),
            let field = cell.subviews.compactMap({ $0 as? NSTextField }).first(where: { $0.tag == position.tag && $0.isEditable })
        else { return }
        outline.scrollRowToVisible(position.row)
        window?.makeFirstResponder(field)
    }

    /// Tab / ⇧Tab move to the next or previous editable cell instead of leaving the table.
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertTab(_:)) || selector == #selector(NSResponder.insertBacktab(_:)),
            let field = control as? NSTextField
        else { return false }
        let row = outline.row(for: field)
        guard row >= 0 else { return false }
        let target = cell(
            after: CellPosition(row: row, tag: field.tag),
            forward: selector == #selector(NSResponder.insertTab(_:)))
        // End editing HERE: the commit rewrites the file and the tree reloads from it; the move
        // is applied once the destination row exists again.
        window?.makeFirstResponder(outline)
        if let target { beginEditingWhenReady(target) }
        return true
    }

    /// The edit lands when the cell ends editing (↩ or focus out); nothing changes for the same
    /// text. The typed text comes from `objectValue` — the formatter put it there unchanged,
    /// while `stringValue` would hand back the DECORATED form and read as an edit every time.
    public func controlTextDidEndEditing(_ n: Notification) {
        guard let field = n.object as? NSTextField, let node = outline.item(atRow: outline.row(for: field)) as? JSONItem else {
            replayPendingLoad()
            return
        }
        defer { replayPendingLoad() }
        let target: EditTarget = field.tag == 1 ? .key : .value
        let typed = (field.objectValue as? String) ?? field.stringValue
        let unchanged = target == .key ? typed == node.label : typed == node.editableValueText
        if unchanged { outline.reloadItem(node); return }
        onEdit?(node, target, typed)  // the node's path names the token in whatever text the host holds now
    }

    /// The cell whose field editor holds the keyboard, or nil.
    private var editingField: NSTextField? {
        guard let editor = window?.firstResponder as? NSTextView, let field = editor.delegate as? NSTextField,
            field.isDescendant(of: outline)
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
            pending()
        }
    }

    /// Opens a cell for editing the way a double-click does and returns what the FIELD EDITOR
    /// shows — the text the user would type over. For the harness: a check that only calls
    /// `commitEditForTesting` never sees what the editor loaded, which is where a decoration bug
    /// would hide.
    @discardableResult
    public func beginEditForTesting(path: String, target: EditTarget) -> String? {
        guard let node = allItems().first(where: { $0.path == path }) else { return nil }
        // Open the way to it first, as clicking the disclosure triangles would: a row that is not
        // visible has no cell to edit.
        for ancestor in allItems() where ancestor !== node && path.hasPrefix(ancestor.path) && ancestor.isExpandable {
            outline.expandItem(ancestor)
        }
        let row = outline.row(forItem: node)
        guard row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: true),
            let field = cell.subviews.compactMap({ $0 as? NSTextField }).first(where: { $0.tag == (target == .key ? 1 : 2) }),
            let window, window.makeFirstResponder(field)
        else { return nil }
        return window.fieldEditor(false, for: field)?.string
    }
    /// Commits whatever the open editor holds, as clicking away does.
    public func endEditForTesting() { window?.makeFirstResponder(outline) }
    /// Types `text` into the open editor, then commits.
    public func typeAndCommitForTesting(_ text: String) {
        if let editor = window?.fieldEditor(false, for: nil) as? NSText { editor.string = text }
        endEditForTesting()
    }

    /// The edit a cell would deliver, for the harness; `path` is the node's JSONPath.
    public func commitEditForTesting(path: String, target: EditTarget, text: String) {
        guard let node = allItems().first(where: { $0.path == path }) else { return }
        onEdit?(node, target, text)
    }
    /// A node's shown value by path, for the harness.
    public func valueTextForTesting(path: String) -> String? { allItems().first { $0.path == path }?.valueText }
    public func typeLabelForTesting(path: String) -> String? { allItems().first { $0.path == path }?.typeLabel }
    public func isExpandedForTesting(path: String) -> Bool {
        allItems().first { $0.path == path }.map { outline.isItemExpanded($0) } ?? false
    }
    /// Whether a node's key cell would open for editing, for the harness.
    public func keyEditableForTesting(path: String) -> Bool { allItems().first { $0.path == path }?.keyIsEditable ?? false }
    /// Every row the outline currently shows, for the harness.
    public var visibleRowCountForTesting: Int { outline.numberOfRows }
    /// The context menu's titles, for the harness.
    public var menuTitlesForTesting: [String] { menuTitlesForTesting(row: -1) }
    /// The menu's titles as opened on `row` (-1: empty space), for the harness.
    public func menuTitlesForTesting(row: Int) -> [String] {
        let menu = NSMenu()
        fillMenu(menu, row: row)
        return menu.items.map(\.title).filter { !$0.isEmpty }
    }
    /// Performs the item titled `title` of the menu as opened on `row` (-1: empty space), for the harness.
    public func performMenuItemForTesting(_ title: String, row: Int = -1) {
        let menu = NSMenu()
        fillMenu(menu, row: row)
        guard let item = menu.items.first(where: { $0.title == title }), let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }
    /// The rendered row's key and value fields as laid out, for the harness.
    public func renderedRowForTesting(path: String) -> (keyWidth: CGFloat, valueText: String, valueWidth: CGFloat)? {
        guard let node = allItems().first(where: { $0.path == path }) else { return nil }
        let row = outline.row(forItem: node)
        guard row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: true) else { return nil }
        cell.layoutSubtreeIfNeeded()
        let fields = cell.subviews.compactMap { $0 as? NSTextField }
        guard let key = fields.first(where: { $0.stringValue == node.label + ":" || $0.stringValue == node.label }),
            let value = fields.first(where: { $0.stringValue == node.valueText && $0 !== key })
        else { return nil }
        return (key.frame.width, value.stringValue, value.frame.width)
    }

    // MARK: - The find bar as a filter

    /// Keeps every node whose key or shown value contains `text`, plus the ancestors that lead
    /// to it, expanded; everything else hides. Returns how many nodes match. An empty text
    /// shows the whole tree again with the expansion it had before the filter.
    @discardableResult
    public func filter(_ text: String, caseSensitive: Bool) -> Int {
        if text.isEmpty {
            guard visible != nil else { return 0 }
            visible = nil; matched = []; query = ""
            outline.reloadData()
            if let saved = expansionBeforeFilter {
                for item in allItems() where saved.contains(ObjectIdentifier(item)) { outline.expandItem(item) }
                expansionBeforeFilter = nil
            }
            if !root.isEmpty { emptyState.hide() }
            return 0
        }
        // The same query again (▲ ▼ re-filter before stepping) keeps the selection where it is.
        if visible != nil, text == query, caseSensitive == queryCaseSensitive { return matched.count }
        if visible == nil { expansionBeforeFilter = Set(allItems().filter { outline.isItemExpanded($0) }.map(ObjectIdentifier.init)) }
        query = text
        queryCaseSensitive = caseSensitive
        var keep = Set<ObjectIdentifier>()
        var hits: [JSONItem] = []
        func mark(_ item: JSONItem) -> Bool {
            var any = false
            for child in item.children where mark(child) { any = true }
            let own = matches(item)
            if own { hits.append(item) }  // after the children: outline order is fixed below
            if own || any { keep.insert(ObjectIdentifier(item)) }
            return own || any
        }
        for item in root { _ = mark(item) }
        visible = keep
        matched = allItems().filter { item in hits.contains { $0 === item } }  // outline (pre-order) order
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)  // only survivors are in the data source now
        if let first = matched.first { select(first) }
        if matched.isEmpty {
            emptyState.show(
                symbol: "magnifyingglass", title: String(localized: "No Matches", bundle: .module),
                subtitle: String(localized: "No key or value contains “\(text)”.", bundle: .module))
        } else if !root.isEmpty {
            emptyState.hide()
        }
        return matched.count
    }

    /// Whether the empty state is up, for the harness.
    public var emptyStateShownForTesting: Bool { !emptyState.isHidden }

    /// ▲ ▼: the next or previous match, wrapping.
    public func selectMatch(forward: Bool) {
        guard !matched.isEmpty else { return }
        let current = matched.firstIndex { outline.row(forItem: $0) == outline.selectedRow } ?? -1
        let next = current < 0 ? 0 : (forward ? (current + 1) % matched.count : (current - 1 + matched.count) % matched.count)
        select(matched[next])
    }

    private func select(_ item: JSONItem) {
        let row = outline.row(forItem: item)
        guard row >= 0 else { return }
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outline.scrollRowToVisible(row)
    }

    private func matches(_ item: JSONItem) -> Bool {
        let options: String.CompareOptions = queryCaseSensitive ? [] : [.caseInsensitive]
        return item.label.range(of: query, options: options) != nil
            || (!item.isExpandable && item.valueText.range(of: query, options: options) != nil)
    }

    /// Every node, pre-order.
    private func allItems() -> [JSONItem] {
        var out: [JSONItem] = []
        func walk(_ item: JSONItem) { out.append(item); item.children.forEach(walk) }
        root.forEach(walk)
        return out
    }

    /// The children the outline shows for `item` (nil: the roots): all of them, or the
    /// filter's survivors.
    private func shownChildren(of item: JSONItem?) -> [JSONItem] {
        let all = item?.children ?? root
        guard let visible else { return all }
        return all.filter { visible.contains(ObjectIdentifier($0)) }
    }

    /// The text with the query's occurrences in the accent colour, for a filtered row.
    private func emphasised(_ text: String, base: NSColor, font: NSFont) -> NSAttributedString {
        let out = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: base])
        guard !query.isEmpty else { return out }
        let ns = text as NSString
        let options: String.CompareOptions = queryCaseSensitive ? [] : [.caseInsensitive]
        var searchRange = NSRange(location: 0, length: ns.length)
        while searchRange.length > 0 {
            let r = ns.range(of: query, options: options, range: searchRange)
            guard r.location != NSNotFound else { break }
            out.addAttributes([.foregroundColor: Theme.accent, .font: NSFont.mono(font.pointSize, weight: .bold)], range: r)
            searchRange = NSRange(location: NSMaxRange(r), length: ns.length - NSMaxRange(r))
        }
        return out
    }

    /// The shown nodes' paths in order, the matched nodes' paths, and the selected node's path,
    /// for the harness; `setExpandedForTesting` drives a root's disclosure.
    public var visiblePathsForTesting: [String] {
        var out: [String] = []
        func walk(_ item: JSONItem?) { for c in shownChildren(of: item) { out.append(c.path); walk(c) } }
        walk(nil)
        return out
    }
    public var matchedPathsForTesting: [String] { matched.map(\.path) }
    public var selectedPathForTesting: String? { (outline.item(atRow: outline.selectedRow) as? JSONItem)?.path }
    /// The selected node's labels from the root down, for the harness.
    public var selectedLabelPathForTesting: [String]? {
        guard outline.selectedRow >= 0, var item = outline.item(atRow: outline.selectedRow) as? JSONItem else { return nil }
        var labels = [item.label]
        while let parent = outline.parent(forItem: item) as? JSONItem { labels.insert(parent.label, at: 0); item = parent }
        return labels
    }
    /// The selected leaf's value as an edit shows it, for the harness.
    public var selectedValueTextForTesting: String? {
        (outline.item(atRow: outline.selectedRow) as? JSONItem).flatMap { $0.isExpandable ? nil : $0.editableValueText }
    }
    /// Clears the selection, for the harness.
    public func deselectAllForTesting() { outline.deselectAll(nil) }
    public func isExpandedForTesting(_ label: String) -> Bool {
        root.first { $0.label == label }.map { outline.isItemExpanded($0) } ?? false
    }
    public func setExpandedForTesting(_ label: String, _ expanded: Bool) {
        guard let item = root.first(where: { $0.label == label }) else { return }
        if expanded { outline.expandItem(item) } else { outline.collapseItem(item) }
    }

    /// The top level's labels in order, for the harness.
    public var rootLabelsForTesting: [String] { root.map(\.label) }
    /// A root node's shown value, for the harness.
    public func valueTextForTesting(_ label: String) -> String? { root.first { $0.label == label }?.valueText }
    /// A top-level item's children's labels, for the harness.
    public func childLabelsForTesting(of label: String) -> [String] { root.first { $0.label == label }?.children.map(\.label) ?? [] }

    // MARK: - Data source

    public func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        shownChildren(of: item as? JSONItem).count
    }
    public func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        shownChildren(of: item as? JSONItem)[index]
    }
    public func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !shownChildren(of: item as? JSONItem).isEmpty
    }

    // MARK: - Expand / collapse

    /// Opens every node — View ▸ Expand All while the tree is on screen, and the menu item.
    public func expandAllNodes() { outline.expandEveryNode() }
    /// Closes every node.
    public func collapseAllNodes() { outline.collapseEveryNode() }

    /// The menu's pair acts on the CLICKED node when it has children (that node and everything
    /// under it), and on the whole tree otherwise — the file tree's rule.
    @objc private func expandAllClicked() {
        guard let node = clickedContainer() else { return expandAllNodes() }
        outline.expandItem(node, expandChildren: true)
    }
    @objc private func collapseAllClicked() {
        guard let node = clickedContainer() else { return collapseAllNodes() }
        outline.collapseItem(node, collapseChildren: true)
    }
    private func clickedContainer() -> JSONItem? {
        guard menuRow >= 0, let node = outline.item(atRow: menuRow) as? JSONItem, node.isExpandable else { return nil }
        return node
    }

    // MARK: - Copy path / value

    @objc private func copyPath() { copy(pathForClickedRow: true) }
    @objc private func copyValue() { copy(pathForClickedRow: false) }
    /// Copies the clicked node's JSONPath (or its value) to the pasteboard.
    /// Falls back to the path for expandable nodes, and unquotes string leaves.
    private func copy(pathForClickedRow wantPath: Bool) {
        guard menuRow >= 0, let node = outline.item(atRow: menuRow) as? JSONItem else { return }
        let text: String
        if wantPath || node.isExpandable {
            text = node.path
        } else if node.valueText.hasPrefix("\""), node.valueText.hasSuffix("\""), node.valueText.count >= 2 {
            text = String(node.valueText.dropFirst().dropLast())  // unquote strings
        } else {
            text = node.valueText
        }
        NSPasteboard.general.copyAndConfirm(
            text,
            receipt: wantPath || node.isExpandable
                ? String(localized: "Copied path", bundle: .module) : String(localized: "Copied value", bundle: .module), in: window)
    }

    // MARK: - Reveal

    /// Whether `label` names nothing an outline lists: a sequence position (`[0]`) or an empty key.
    public static func isUnnamed(_ label: String) -> Bool {
        label.isEmpty
            || (label.count >= 3 && label.first == "[" && label.last == "]" && label.dropFirst().dropLast().allSatisfy(\.isNumber))
    }

    /// The label paths an outline's `keyPath` may stand for, in the order ``reveal(keyPath:occurrence:)``
    /// tries them: as written, then with TOML dotted keys split (`site.name` is `site › name`).
    public static func labelPaths(for keyPath: [String]) -> [[String]] {
        let dotted = keyPath.flatMap(dottedParts)
        return dotted == keyPath ? [keyPath] : [keyPath, dotted]
    }

    /// Selects the `occurrence`-th node (0-based, in display order) whose labels from the root are
    /// `keyPath` — sequence positions and empty keys skipped, as an outline does not name them —
    /// opening its ancestors and scrolling it into view. An outline that names a node by an
    /// attribute's value (an XSLT template by its `match`) lands on that attribute. False when
    /// nothing matches. The outline's click lands here while the tree is on screen.
    @discardableResult
    public func reveal(keyPath: [String], occurrence: Int = 0) -> Bool {
        for candidate in Self.labelPaths(for: keyPath) where !candidate.isEmpty {
            var matches: [[JSONItem]] = []
            func walk(_ items: [JSONItem], chain: [JSONItem], names: [String]) {
                for item in items {
                    let path = chain + [item]
                    let unnamed = Self.isUnnamed(item.label)
                    let named = unnamed ? names : names + [item.label]
                    if named == candidate, !unnamed { matches.append(path) }
                    if named.count <= candidate.count, zip(named, candidate).allSatisfy(==) {
                        walk(item.children, chain: path, names: named)
                    }
                }
            }
            walk(root, chain: [], names: [])
            if select(matches, occurrence: occurrence) { return true }
        }
        guard keyPath.count == 1, let name = keyPath.first else { return false }
        return select(leaves(valued: name), occurrence: occurrence)
    }

    /// Every leaf (with its ancestors) whose value reads `text`, in display order.
    private func leaves(valued text: String) -> [[JSONItem]] {
        var matches: [[JSONItem]] = []
        func walk(_ items: [JSONItem], chain: [JSONItem]) {
            for item in items {
                if item.isExpandable {
                    walk(item.children, chain: chain + [item])
                } else if item.editableValueText == text {
                    matches.append(chain + [item])
                }
            }
        }
        walk(root, chain: [])
        return matches
    }

    /// Opens the ancestors of the `occurrence`-th path (the last when there are fewer), selects
    /// its node and scrolls to it; false when `paths` is empty.
    private func select(_ paths: [[JSONItem]], occurrence: Int) -> Bool {
        guard !paths.isEmpty else { return false }
        let path = paths[min(occurrence, paths.count - 1)]
        for ancestor in path.dropLast() { outline.expandItem(ancestor) }
        let row = outline.row(forItem: path.last)
        guard row >= 0 else { return false }
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outline.scrollRowToVisible(row)
        return true
    }

    /// A TOML dotted key's parts (`fruit."apple.pie".color` → fruit, apple.pie, color).
    static func dottedParts(_ key: String) -> [String] {
        var parts: [String] = [], current = "", quote: Character?
        for ch in key {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == "." {
                parts.append(current.trimmingCharacters(in: .whitespaces)); current = ""
            } else {
                current.append(ch)
            }
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts
    }

    // MARK: - Context menu

    /// Fills `menu` for a click on `row`: on a row, its path, value and (for a branch) the branch as
    /// JSON, then expand/collapse for that node; on empty space, the whole document as JSON or YAML
    /// in file order — what gets pasted to an agent — then Expand All / Collapse All.
    private func fillMenu(_ menu: NSMenu, row: Int) {
        menu.removeAllItems()
        menuRow = row
        let node = row >= 0 ? outline.item(atRow: row) as? JSONItem : nil
        if let node {
            menu.addItem(
                String(localized: "Copy Path", bundle: .module), action: #selector(copyPath), target: self,
                symbol: "arrow.right.doc.on.clipboard")
            if !node.isExpandable {
                menu.addItem(
                    String(localized: "Copy Value", bundle: .module), action: #selector(copyValue), target: self, symbol: "doc.on.doc")
            }
            if node.isExpandable, rootValue?.value(at: node.components) != nil {
                menu.addItem(
                    String(
                        localized: "Copy as JSON", bundle: .module,
                        comment: "Structure tree menu: copy the clicked branch, or the whole document, as JSON"),
                    action: #selector(copyBranchJSON), target: self, symbol: "curlybraces")
            }
            guard node.isExpandable else { return }
            menu.addItem(.separator())
            menu.addItem(
                String(localized: "Expand All", bundle: .module), action: #selector(expandAllClicked), target: self,
                symbol: "arrow.down.right.and.arrow.up.left.rectangle")
            menu.addItem(
                String(localized: "Collapse All", bundle: .module), action: #selector(collapseAllClicked), target: self,
                symbol: "arrow.up.left.and.arrow.down.right.rectangle")
            return
        }
        if rootValue != nil {
            menu.addItem(
                String(localized: "Copy as JSON", bundle: .module), action: #selector(copyDocumentJSON), target: self, symbol: "curlybraces"
            )
            menu.addItem(
                String(localized: "Copy as YAML", bundle: .module, comment: "Structure tree menu: copy the whole document as YAML"),
                action: #selector(copyDocumentYAML), target: self, symbol: "list.bullet.indent")
            menu.addItem(.separator())
        }
        menu.addItem(
            String(localized: "Expand All", bundle: .module), action: #selector(expandAllClicked), target: self,
            symbol: "arrow.down.right.and.arrow.up.left.rectangle")
        menu.addItem(
            String(localized: "Collapse All", bundle: .module), action: #selector(collapseAllClicked), target: self,
            symbol: "arrow.up.left.and.arrow.down.right.rectangle")
    }

    public func menuNeedsUpdate(_ menu: NSMenu) { fillMenu(menu, row: outline.clickedRow) }

    @objc private func copyBranchJSON() {
        guard menuRow >= 0, let node = outline.item(atRow: menuRow) as? JSONItem, let value = rootValue?.value(at: node.components) else {
            return
        }
        NSPasteboard.general.copyAndConfirm(value.jsonText(), receipt: String(localized: "Copied as JSON", bundle: .module), in: window)
    }
    @objc private func copyDocumentJSON() {
        guard let rootValue else { return }
        NSPasteboard.general.copyAndConfirm(rootValue.jsonText(), receipt: String(localized: "Copied as JSON", bundle: .module), in: window)
    }
    @objc private func copyDocumentYAML() {
        guard let rootValue else { return }
        NSPasteboard.general.copyAndConfirm(rootValue.yamlText(), receipt: String(localized: "Copied as YAML", bundle: .module), in: window)
    }

    /// A Foundation JSON object as a structured value (keys sorted), for JSON the ordered reader
    /// could not take (JSONC/JSON5 read leniently).
    private static func structuredValue(_ obj: Any) -> StructuredValue {
        switch obj {
        case let dict as [String: Any]:
            return .mapping(dict.keys.sorted().map { StructuredPair(key: $0, value: structuredValue(dict[$0] ?? NSNull())) })
        case let array as [Any]: return .sequence(array.map(structuredValue))
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            return number.doubleValue == number.doubleValue.rounded() && abs(number.doubleValue) < 9e15
                ? .integer(number.intValue) : .number(number.doubleValue)
        case let string as String: return .string(string)
        default: return .null
        }
    }

    // MARK: - Delegate

    /// The theme's selection, not AppKit's accent blue: the cells keep their own colours on it.
    public func outlineView(_ ov: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        ov.reusableView { ThemedPlainRowView(accentBar: 0) }
    }

    /// Builds a row cell: glyph, key (with trailing `:` for leaves), colored
    /// truncating value, and a right-aligned type badge; tooltip is the node path.
    public func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? JSONItem else { return nil }
        let cell = NSTableCellView()
        cell.toolTip = node.path
        let glyph = NSTextField.label(node.glyph, font: .mono(9), color: Theme.statusText)
        glyph.setContentHuggingPriority(.required, for: .horizontal)
        let key = NSTextField.label(
            node.isExpandable ? node.label : node.label + ":", font: .mono(12, weight: .medium), color: Theme.property)
        key.setContentHuggingPriority(.required, for: .horizontal)
        let value = NSTextField.label(node.valueText, font: .mono(12), color: node.color, lineBreak: .byTruncatingTail)
        value.usesSingleLineMode = true
        value.cell?.usesSingleLineMode = true
        value.maximumNumberOfLines = 1
        // A member's key and a scalar's value edit in place (the .env table's recipe): the field
        // editor is the window's configured one, so autocorrect and Writing Tools stay out.
        for (field, editable, tag, decoration) in [
            (key, node.keyIsEditable, 1, node.keyDecoration),
            (value, node.valueIsEditable, 2, node.valueDecoration),
        ] where editable && visible == nil && !isReadOnly {
            field.isEditable = true
            field.isSelectable = true
            field.focusRingType = .none
            field.delegate = self
            field.tag = tag
            field.disableSystemTextIntelligence()
            // The row SHOWS `"nginx"` / `image:` and EDITS `nginx` / `image`: the decoration is a
            // formatter, never a text swap when editing begins — that does not reach the field
            // editor, and each double-click would quote the value again.
            field.formatter = CellEditFormatter(prefix: decoration.prefix, suffix: decoration.suffix)
            field.objectValue = tag == 1 ? node.label : node.editableValueText
        }
        // An EDITABLE NSTextField has no intrinsic width (AppKit expects constraints to size a
        // field you can type into), so an editable key would take the whole row and leave the
        // value after it zero wide. The key keeps its label's width by constraint; the value
        // takes the rest.
        if key.isEditable {
            key.pinSize(width: ceil(key.cell?.cellSize.width ?? 0) + 2)
        }
        if visible != nil {
            // Filtering: a match wears the query in the accent; a row kept only as the way to
            // one reads dimmed.
            let isMatch = matched.contains { $0 === node }
            let keyBase = isMatch ? Theme.property : Theme.property.withAlphaComponent(0.55)
            let valueBase = isMatch ? node.color : node.color.withAlphaComponent(0.55)
            key.attributedStringValue = emphasised(key.stringValue, base: keyBase, font: key.font!)
            value.attributedStringValue = emphasised(node.valueText, base: valueBase, font: value.font!)
        }
        let type = NSTextField.label(
            node.typeLabel, font: Theme.uiFontSmall, color: Theme.statusText.withAlphaComponent(0.55), alignment: .right)
        type.setContentCompressionResistancePriority(.required, for: .horizontal)
        cell.addSubviewsForAutoLayout(glyph, key, value, type)
        NSLayoutConstraint.activate([
            glyph.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            glyph.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            key.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 6),
            key.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            value.leadingAnchor.constraint(equalTo: key.trailingAnchor, constant: 8),
            value.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            value.trailingAnchor.constraint(lessThanOrEqualTo: type.leadingAnchor, constant: -8),
            type.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            type.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
