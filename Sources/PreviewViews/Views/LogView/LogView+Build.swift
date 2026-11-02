//
//  LogView+Build.swift
//  PreviewViews
//
//  LogView: the bar, the table and the entry pane, laid out.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import AppKitViews
import LogReader
import ThemedControls

extension LogView {
    /// The columns, in order: their identifiers, titles and widths (0 for the one that takes the rest).
    static let columns: [(id: String, title: String, width: CGFloat)] = [
        ("time", String(localized: "Time", bundle: .module, comment: "Log view column: when the entry was written"), 178),
        ("level", String(localized: "Level", bundle: .module, comment: "Log view column: the entry's severity"), 64),
        ("component", String(localized: "Component", bundle: .module, comment: "Log view column: the logger, service or program"), 130),
        ("message", String(localized: "Message", bundle: .module, comment: "Log view column: the entry's text"), 0),
    ]

    func build() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        buildBar()
        buildTable()
        buildDetail()
        hairline.wantsLayer = true
        split.isVertical = false
        split.dividerStyle = .thin
        split.addArrangedSubview(tableScroll)
        split.addArrangedSubview(detailScroll)
        split.setHoldingPriority(.defaultLow - 1, forSubviewAt: 0)
        split.setHoldingPriority(.defaultLow + 1, forSubviewAt: 1)
        addSubviewsForAutoLayout(bar, hairline, split)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            bar.heightAnchor.constraint(equalToConstant: 26),
            hairline.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 6),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
            split.topAnchor.constraint(equalTo: hairline.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: leadingAnchor),
            split.trailingAnchor.constraint(equalTo: trailingAnchor),
            split.bottomAnchor.constraint(equalTo: bottomAnchor),
            detailScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            tableScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
        emptyState.install(over: tableScroll)
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
    }

    /// The level boxes (most severe first, each hidden until its level occurs), Other for entries with no level,
    /// the component and time menus, Follow, and the summary.
    private func buildBar() {
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.alignment = .centerY
        bar.detachesHiddenViews = true
        for level in LogLevel.allCases.reversed() {
            let box = checkbox(Self.levelTitle(level), action: #selector(levelBoxClicked(_:)))
            box.tag = level.rawValue
            levelBoxes[level] = box
            bar.addArrangedSubview(box)
        }
        unleveledBox.title = String(localized: "Other", bundle: .module, comment: "Log view: entries with no level")
        configure(unleveledBox, action: #selector(levelBoxClicked(_:)))
        unleveledBox.tag = -1
        bar.addArrangedSubview(unleveledBox)
        for button in [componentButton, timeButton] {
            button.font = Theme.uiFontSmall
            button.controlSize = .small
            button.target = self
            bar.addArrangedSubview(button)
        }
        followBox.title = String(localized: "Follow", bundle: .module, comment: "Log view: keep the newest entry in view as the file grows")
        configure(followBox, action: #selector(followClicked))
        followBox.state = .off  // never on unasked: following moves what the person is reading
        bar.addArrangedSubview(followBox)
        summaryLabel.font = Theme.uiFontSmall
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.setContentCompressionResistancePriority(.defaultLow - 10, for: .horizontal)
        summaryLabel.setContentHuggingPriority(.defaultLow - 10, for: .horizontal)
        bar.addArrangedSubview(summaryLabel)
        for view in bar.arrangedSubviews where view !== summaryLabel {
            view.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        }
    }

    private func checkbox(_ title: String, action: Selector) -> ThemedCheckbox {
        let box = ThemedCheckbox()
        box.title = title
        configure(box, action: action)
        return box
    }

    private func configure(_ box: ThemedCheckbox, action: Selector) {
        box.font = Theme.uiFontSmall
        box.state = .on
        box.target = self
        box.action = action
    }

    private func buildTable() {
        tableView.headerView = ThemedTableHeaderView()
        for spec in Self.columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.title = spec.title
            column.headerCell = ThemedTableHeaderCell(title: spec.title, titleInset: 6)
            if spec.width > 0 {
                column.width = spec.width
                column.minWidth = 40
            } else {
                column.width = 600
                column.minWidth = 120
            }
            tableView.addTableColumn(column)
        }
        tableView.backgroundColor = .clear
        tableView.rowHeight = 20
        tableView.intercellSpacing = NSSize(width: 6, height: 0)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.allowsColumnReordering = false
        tableView.allowsMultipleSelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(revealClicked)
        tableView.setAccessibilityLabel(String(localized: "Log entries", bundle: .module, comment: "Accessibility: the log table's name"))
        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = true
        tableScroll.drawsBackground = false
        tableScroll.documentView = tableView
    }

    private func buildDetail() {
        detailView.isEditable = false
        detailView.isSelectable = true
        detailView.isRichText = false
        detailView.font = Theme.editorFont
        detailView.textContainerInset = NSSize(width: 8, height: 6)
        detailView.disableWritingTools()
        detailView.isVerticallyResizable = true
        detailView.isHorizontallyResizable = false
        detailView.autoresizingMask = [.width]
        detailView.textContainer?.widthTracksTextView = true
        detailView.minSize = NSSize(width: 0, height: 0)
        detailView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        detailScroll.hasVerticalScroller = true
        detailScroll.drawsBackground = false
        detailScroll.documentView = detailView
    }

    /// A level's name for its box: the word, in the person's language.
    static func levelTitle(_ level: LogLevel) -> String {
        switch level {
        case .trace: return String(localized: "Trace", bundle: .module, comment: "Log level")
        case .debug: return String(localized: "Debug", bundle: .module, comment: "Log level")
        case .info: return String(localized: "Info", bundle: .module, comment: "Log level")
        case .notice: return String(localized: "Notice", bundle: .module, comment: "Log level")
        case .warning: return String(localized: "Warning", bundle: .module, comment: "Log level")
        case .error: return String(localized: "Error", bundle: .module, comment: "Log level")
        case .fatal: return String(localized: "Fatal", bundle: .module, comment: "Log level")
        }
    }

    /// A level as the table writes it: a log's own short capitals.
    static func levelCode(_ level: LogLevel) -> String {
        switch level {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .fatal: return "FATAL"
        }
    }

    /// A level's colour: errors in the removal colour, warnings in the warning colour, debug and trace muted.
    static func levelColour(_ level: LogLevel?) -> NSColor {
        switch level {
        case .fatal?, .error?: return Theme.removed
        case .warning?: return Theme.warning
        case .notice?: return Theme.accent
        case .info?: return Theme.foreground
        case .debug?, .trace?, nil: return Theme.mutedText
        }
    }
}
