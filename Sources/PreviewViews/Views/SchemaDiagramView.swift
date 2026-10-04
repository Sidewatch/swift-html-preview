//
//  SchemaDiagramView.swift
//  Sidewatch
//
//  A visual entity-relationship diagram of a SQLite schema: each table is a box (columns, PK/FK
//  marked), foreign keys are connector lines.
//
//  Created by David Sherlock on 7/8/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import ThemedControls
import SQLiteReader
import AppKitViews

/// A visual entity-relationship diagram of a SQLite schema: each table is a box
/// (columns, PK/FK marked), foreign keys are connector lines. Masonry auto-layout,
/// scrolls inside its enclosing scroll view. Boxes are draggable — FK connectors
/// re-route live — and dragged positions persist per database (UserDefaults keyed
/// by db path + table name). Double-click the background to re-run auto-layout
/// (clears the saved positions). Click a box (without dragging) to select its table.
public final class SchemaDiagramView: NSView {
    private struct Col { let name: String; let type: String; let pk: Bool; let fk: Bool }
    private struct Box { let table: String; let columns: [Col]; var frame: NSRect }
    private struct Edge { let from: String; let fromCol: String; let to: String }

    /// Fired when a table box is clicked (a click, not a drag) — lets the host
    /// jump to / focus that table.
    public var onSelectTable: ((String) -> Void)?
    private var boxes: [Box] = []
    private var edges: [Edge] = []
    private var rowIndex: [String: [String: Int]] = [:]
    /// Centered over the canvas when the schema has no tables to diagram.
    private let emptyState = EmptyStateView(
        symbol: "circle.grid.cross", title: String(localized: "No Tables", bundle: .module),
        subtitle: String(localized: "No tables to diagram.", bundle: .module))

    /// Persistence key for dragged positions (the database file's path); nil = no persistence.
    private var positionsKey: String?
    private static let defaultsKeyPrefix = "SchemaDiagramPositions."

    // Drag session (nil/false when idle).
    private var dragIndex: Int?
    private var dragOffset = NSPoint.zero
    private var dragStart = NSPoint.zero
    private var dragMoved = false
    /// A reload that arrived mid-drag (status ticks re-render the preview); replayed
    /// on mouseUp so the rebuild can't yank the boxes out from under the cursor.
    private var pendingLoad: (db: SQLiteDB, tables: [String], key: String?)?

    private let rowH: CGFloat = 19
    private let headerH: CGFloat = 26
    private let boxW: CGFloat = 214
    private let padX: CGFloat = 46
    private let padY: CGFloat = 34

    public override var isFlipped: Bool { true }

    /// Forgets what it was drawing — a new file with nothing to draw must not leave the last
    /// one's boxes on screen.
    public func clear() {
        boxes = []
        edges = []
        rowIndex = [:]
        needsDisplay = true
    }

    /// Rebuilds the diagram from `db`: reads each table's columns + foreign keys,
    /// runs the masonry auto-layout, then overrides box origins with any positions
    /// previously dragged + saved for `key`, sizes the view to fit and repaints.
    public func load(_ db: SQLiteDB, tables: [String], key: String? = nil) {
        if dragIndex != nil {  // mid-drag — defer, replayed on mouseUp
            pendingLoad = (db, tables, key)
            return
        }
        pendingLoad = nil
        positionsKey = key
        boxes = []; edges = []; rowIndex = [:]

        for t in tables {
            let schema = db.schema(t)
            let fks = db.foreignKeys(t)
            let fkCols = Set(fks.map { $0.from })
            let cols = schema.map { Col(name: $0.name, type: $0.type, pk: $0.pk, fk: fkCols.contains($0.name)) }
            let h = headerH + CGFloat(max(cols.count, 1)) * rowH + 8
            boxes.append(Box(table: t, columns: cols, frame: NSRect(x: 0, y: 0, width: boxW, height: h)))

            var idx: [String: Int] = [:]
            for (r, col) in cols.enumerated() { idx[col.name] = r }
            rowIndex[t] = idx
            for fk in fks { edges.append(Edge(from: t, fromCol: fk.from, to: fk.toTable)) }
        }

        autoLayout()
        let saved = savedPositions()
        if !saved.isEmpty {
            for i in boxes.indices {
                guard let p = saved[boxes[i].table] else { continue }
                boxes[i].frame.origin = NSPoint(x: max(0, p.x), y: max(0, p.y))
            }
        }
        sizeToFitBoxes()
        updateEmptyState()
        needsDisplay = true
    }

    /// Adds the empty-state overlay (once, pinned centered) and toggles it: shown
    /// when the schema has no tables to diagram, hidden as soon as any box exists.
    private func updateEmptyState() {
        if emptyState.superview == nil {
            emptyState.isHidden = true
            addSubview(emptyState)
            NSLayoutConstraint.activate([
                emptyState.centerXAnchor.constraint(equalTo: centerXAnchor),
                emptyState.centerYAnchor.constraint(equalTo: centerYAnchor),
                emptyState.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
                emptyState.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            ])
        }
        if boxes.isEmpty {
            emptyState.show(
                symbol: "circle.grid.cross", title: String(localized: "No Tables", bundle: .module),
                subtitle: String(localized: "No tables to diagram.", bundle: .module))
        } else {
            emptyState.hide()
        }
    }

    /// Masonry auto-layout: stacks the existing boxes round-robin across up-to-4
    /// columns (`colHeights` tracks each column's running Y).
    private func autoLayout() {
        let perCol = max(1, min(4, boxes.count))
        var colHeights = [CGFloat](repeating: padY, count: perCol)
        for i in boxes.indices {
            let c = i % perCol
            boxes[i].frame.origin = NSPoint(x: padX + CGFloat(c) * (boxW + padX), y: colHeights[c])
            colHeights[c] += boxes[i].frame.height + padY
        }
    }

    /// Sizes the view to enclose every box (plus padding), never smaller than the
    /// clip view — so background double-clicks land on this view anywhere.
    private func sizeToFitBoxes() {
        var w = max((boxes.map { $0.frame.maxX }.max() ?? 0) + padX, 400)
        var h = max((boxes.map { $0.frame.maxY }.max() ?? 0) + padY, 300)
        if let clip = enclosingScrollView?.contentView {
            w = max(w, clip.bounds.width)
            h = max(h, clip.bounds.height)
        }
        setFrameSize(NSSize(width: w, height: h))
    }

    // MARK: - Dragging / clicking / reset

    /// Double-click on the background re-runs auto-layout (clearing saved positions);
    /// a single press on a box starts a potential drag (raised to the top so it draws
    /// over its siblings). Whether it was a click or a drag is decided in `mouseUp`.
    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 {
            if boxes.last(where: { $0.frame.contains(p) }) == nil { resetLayout() }
            return
        }
        dragMoved = false
        dragStart = p
        // Topmost box under the cursor = the LAST one drawn.
        guard let idx = boxes.lastIndex(where: { $0.frame.contains(p) }) else { dragIndex = nil; return }
        let box = boxes.remove(at: idx)
        boxes.append(box)
        dragIndex = boxes.count - 1
        dragOffset = NSPoint(x: p.x - box.frame.minX, y: p.y - box.frame.minY)
        needsDisplay = true
    }

    /// Moves the pressed box with the cursor (clamped to the top-left content edge,
    /// growing the view when dragged past the current bounds). The full redraw
    /// re-routes every FK connector live — edges read box frames at draw time.
    public override func mouseDragged(with event: NSEvent) {
        guard let idx = dragIndex else { return }
        let p = convert(event.locationInWindow, from: nil)
        if !dragMoved, hypot(p.x - dragStart.x, p.y - dragStart.y) > 3 { dragMoved = true }
        guard dragMoved else { return }
        boxes[idx].frame.origin = NSPoint(x: max(0, p.x - dragOffset.x), y: max(0, p.y - dragOffset.y))
        // Grow (never shrink) mid-drag so the box can be pulled beyond the edge.
        let needW = boxes[idx].frame.maxX + padX, needH = boxes[idx].frame.maxY + padY
        if needW > frame.width || needH > frame.height {
            setFrameSize(NSSize(width: max(needW, frame.width), height: max(needH, frame.height)))
        }
        autoscroll(with: event)
        needsDisplay = true
    }

    /// Ends the session: a genuine drag settles the layout (shrink-wrap + persist);
    /// a plain click reports the table selection. Either way, any reload deferred
    /// mid-session is replayed (after persisting, so the rebuild keeps the arrangement).
    public override func mouseUp(with event: NSEvent) {
        guard let idx = dragIndex else { return }
        dragIndex = nil
        let table = boxes[idx].table
        if dragMoved {
            sizeToFitBoxes()
            savePositions()
            needsDisplay = true
        }
        if let p = pendingLoad { pendingLoad = nil; load(p.db, tables: p.tables, key: p.key) }
        if !dragMoved { onSelectTable?(table) }
    }

    /// Persists every box's origin for this database (whole-diagram snapshot — one
    /// drag freezes the arrangement until the background is double-clicked).
    private func savePositions() {
        guard let key = positionsKey else { return }
        var dict: [String: [Double]] = [:]
        for b in boxes { dict[b.table] = [b.frame.minX, b.frame.minY] }
        UserDefaults.standard.set(dict, forKey: Self.defaultsKeyPrefix + key)
    }

    /// The saved origins for this database, if any were persisted.
    private func savedPositions() -> [String: NSPoint] {
        guard let key = positionsKey,
            let dict = UserDefaults.standard.dictionary(forKey: Self.defaultsKeyPrefix + key)
        else { return [:] }
        var out: [String: NSPoint] = [:]
        for (table, v) in dict {
            guard let xy = v as? [Double], xy.count == 2 else { continue }
            out[table] = NSPoint(x: xy[0], y: xy[1])
        }
        return out
    }

    /// Background double-click: forget the saved arrangement and re-flow the boxes.
    private func resetLayout() {
        if let key = positionsKey {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKeyPrefix + key)
        }
        autoLayout()
        sizeToFitBoxes()
        needsDisplay = true
    }

    /// Paints the background, then FK edges, then boxes on top (edges behind boxes).
    public override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        dirtyRect.fill()
        for e in edges { drawEdge(e) }  // lines behind boxes
        for b in boxes { drawBox(b) }
    }

    /// Renders one table box: rounded fill, bold table-name header, a separator,
    /// then each column row (FK dot, PK accent-colored name, right-aligned type).
    private func drawBox(_ b: Box) {
        let path = NSBezierPath(roundedRect: b.frame, xRadius: 6, yRadius: 6)
        Theme.sidebarBg.setFill(); path.fill()

        draw(
            b.table, in: NSRect(x: b.frame.minX + 10, y: b.frame.minY + 5, width: b.frame.width - 20, height: 16),
            font: .systemFont(ofSize: 12, weight: .bold), color: Theme.foreground)

        let sepY = b.frame.minY + headerH
        Theme.border.setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: b.frame.minX, y: sepY)); sep.line(to: NSPoint(x: b.frame.maxX, y: sepY))
        sep.lineWidth = 1; sep.stroke()

        for (i, c) in b.columns.enumerated() {
            let ry = b.frame.minY + headerH + CGFloat(i) * rowH
            if c.fk {
                Theme.accent.setFill()
                NSBezierPath(ovalIn: NSRect(x: b.frame.minX + 7, y: ry + rowH / 2 - 2, width: 4, height: 4)).fill()
            }
            draw(
                c.name, in: NSRect(x: b.frame.minX + 16, y: ry + 1, width: b.frame.width * 0.54 - 16, height: rowH),
                font: .mono(10, weight: c.pk ? .semibold : .regular),
                color: c.pk ? Theme.accent : Theme.foreground)
            draw(
                c.type, in: NSRect(x: b.frame.minX + b.frame.width * 0.54, y: ry + 1, width: b.frame.width * 0.46 - 10, height: rowH),
                font: .mono(9), color: Theme.statusText, align: .right)
        }

        Theme.border.setStroke(); path.lineWidth = 1; path.stroke()
    }

    /// Draws a foreign-key connector as a Bézier curve from the source column's row
    /// to the target table's header, exiting whichever side faces the target. No-op
    /// if either endpoint table isn't laid out.
    private func drawEdge(_ e: Edge) {
        guard let from = boxes.first(where: { $0.table == e.from }),
            let to = boxes.first(where: { $0.table == e.to })
        else { return }
        let r = rowIndex[e.from]?[e.fromCol] ?? 0
        let fy = from.frame.minY + headerH + CGFloat(r) * rowH + rowH / 2
        let toRight = to.frame.midX >= from.frame.midX
        let fx = toRight ? from.frame.maxX : from.frame.minX
        let tx = toRight ? to.frame.minX : to.frame.maxX
        let ty = to.frame.minY + headerH / 2

        let path = NSBezierPath()
        path.move(to: NSPoint(x: fx, y: fy))
        let dx = max(30, abs(tx - fx) * 0.5)
        path.curve(
            to: NSPoint(x: tx, y: ty),
            controlPoint1: NSPoint(x: fx + (toRight ? dx : -dx), y: fy),
            controlPoint2: NSPoint(x: tx + (toRight ? -dx : dx), y: ty))
        Theme.accent.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        Theme.accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: fx - 2.5, y: fy - 2.5, width: 5, height: 5)).fill()
        NSBezierPath(ovalIn: NSRect(x: tx - 3, y: ty - 3, width: 6, height: 6)).fill()
    }

    /// Text-drawing helper: single-line, tail-truncated string draw with the given font/color/alignment.
    private func draw(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, align: NSTextAlignment = .left) {
        let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
    }
}
