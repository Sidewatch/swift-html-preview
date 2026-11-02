//
//  LogView+Menu.swift
//  PreviewViews
//
//  LogView: a row's menu — copy, a time range from an entry, one component, the line in the editor.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import AppKitViews
import LogReader

extension LogView: NSMenuDelegate {
    /// Built per click, for the clicked row (or the selection it is part of).
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clicked = tableView.clickedRow
        if clicked >= 0, !tableView.selectedRowIndexes.contains(clicked) {
            tableView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        }
        guard let entry = selectedEntries.first else { return }
        let many = selectedEntries.count > 1
        add(
            menu,
            many
                ? String(localized: "Copy Entries", bundle: .module, comment: "Log view menu: copy the selected entries")
                : String(localized: "Copy Entry", bundle: .module, comment: "Log view menu: copy the entry, every line"),
            #selector(copyEntries))
        if !many {
            add(
                menu, String(localized: "Copy Message", bundle: .module, comment: "Log view menu: copy the message alone"),
                #selector(copyMessage))
        }
        if entry.time != nil {
            menu.addItem(.separator())
            add(
                menu, String(localized: "Show From Here", bundle: .module, comment: "Log view menu: show entries from this one's time on"),
                #selector(showFromHere))
            add(
                menu, String(localized: "Show Up To Here", bundle: .module, comment: "Log view menu: show entries up to this one's time"),
                #selector(showUpToHere))
        }
        if let component = entry.component {
            menu.addItem(.separator())
            let item = add(
                menu, String(localized: "Only \(component)", bundle: .module, comment: "Log view menu: show only this component's entries"),
                #selector(onlyComponent(_:)))
            item.representedObject = component
        }
        if onReveal != nil {
            menu.addItem(.separator())
            add(
                menu, String(localized: "Show in Editor", bundle: .module, comment: "Log view menu: open the file at this entry's line"),
                #selector(revealClicked))
        }
    }

    @discardableResult private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc func copyEntries() {
        guard let index else { return }
        put(selectedEntries.map { index.text(of: $0) }.joined(separator: "\n"))
    }

    @objc func copyMessage() {
        guard let entry = selectedEntries.first else { return }
        put(message(of: entry))
    }

    @objc func showFromHere() {
        guard let time = selectedEntries.first?.time?.seconds else { return }
        if case .range(_, let to) = timeWindow { timeWindow = .range(from: time, to: to) } else { timeWindow = .range(from: time, to: nil) }
        syncControls()
        refilter()
    }

    @objc func showUpToHere() {
        guard let time = selectedEntries.last?.time?.seconds else { return }
        if case .range(let from, _) = timeWindow {
            timeWindow = .range(from: from, to: time)
        } else {
            timeWindow = .range(from: nil, to: time)
        }
        syncControls()
        refilter()
    }

    @objc func onlyComponent(_ item: NSMenuItem) {
        guard let name = item.representedObject as? String else { return }
        filter.components = [name]
        syncControls()
        refilter()
    }

    @objc func revealClicked() {
        guard let entry = selectedEntries.first else { return }
        onReveal?(entry.firstLine)
    }

    private func put(_ text: String) { _ = NSPasteboard.general.copy(text) }

    /// ⌘C copies the selected entries.
    @objc public func copy(_ sender: Any?) { copyEntries() }
}
