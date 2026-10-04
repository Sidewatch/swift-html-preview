//
//  DatabasePreviewView.swift
//  PreviewViews
//
//  The Quick Look database preview: the app's browser, read-only, with its views a click apart.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import AppKitViews
import CodeLanguage
import ThemedControls

/// The Quick Look database preview: the app's browser, read-only, under a segment bar for its views
/// — Results, Structure, Diagram — and the schema as SQL. The app switches these from its
/// breadcrumb; Quick Look has no breadcrumb, so the bar lives here, outside the browser.
public final class DatabasePreviewView: NSView {
    /// The browser, read-only: no console, no + Row, no cell edits, opened without write access.
    public let database = DatabaseView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    private let bar = ThemedSegmentBar(
        labels: [
            String(localized: "Results", bundle: .module, comment: "Quick Look database preview: the rows of a table"),
            String(localized: "Structure", bundle: .module, comment: "Quick Look database preview: a table's columns and keys"),
            String(localized: "Diagram", bundle: .module, comment: "Quick Look database preview: the tables and their relations"),
            String(localized: "Schema SQL", bundle: .module, comment: "Quick Look database preview: every CREATE statement"),
        ],
        symbols: [
            "tablecells", "list.bullet.rectangle", "point.3.connected.trianglepath.dotted", "chevron.left.forwardslash.chevron.right",
        ])
    private let url: URL
    private var schema: CodePreviewView?

    public init(url: URL) {
        self.url = url
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        wantsLayer = true
        database.isReadOnly = true
        database.load(url)
        bar.target = self
        bar.action = #selector(barChanged)
        bar.selectedSegment = database.mode.rawValue
        bar.setAccessibilityLabel(
            String(localized: "Database view", bundle: .module, comment: "Quick Look database preview: the view switch"))
        addSubviewsForAutoLayout(bar, database)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            bar.centerXAnchor.constraint(equalTo: centerXAnchor),
            database.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            database.leadingAnchor.constraint(equalTo: leadingAnchor),
            database.trailingAnchor.constraint(equalTo: trailingAnchor),
            database.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        layer?.backgroundColor = Theme.sidebarBg.cgColor
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    @objc private func barChanged() { show(segment: bar.selectedSegment) }

    /// Shows segment `index`: one of the browser's three views, or the schema's SQL.
    private func show(segment index: Int) {
        if let mode = DatabaseView.Mode(rawValue: index) {
            schema?.isHidden = true
            database.isHidden = false
            database.setMode(mode, notify: false)
            return
        }
        let code = schema ?? makeSchemaView()
        code.isHidden = false
        database.isHidden = true
    }

    private func makeSchemaView() -> CodePreviewView {
        let code = CodePreviewView(text: DatabaseView.schemaSQL(of: url), language: .sql)
        addSubviewsForAutoLayout(code)
        NSLayoutConstraint.activate([
            code.topAnchor.constraint(equalTo: database.topAnchor),
            code.leadingAnchor.constraint(equalTo: leadingAnchor),
            code.trailingAnchor.constraint(equalTo: trailingAnchor),
            code.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        schema = code
        return code
    }

    /// Picks segment `index` as a click would, for the harness.
    public func selectForTesting(_ index: Int) { bar.select(index) }
    /// Whether the schema's SQL is the view on show, for the harness.
    public var showsSchemaForTesting: Bool { schema.map { !$0.isHidden } ?? false }
}
