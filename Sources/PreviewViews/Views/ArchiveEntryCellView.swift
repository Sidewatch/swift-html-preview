//
//  ArchiveEntryCellView.swift
//  PreviewViews
//
//  One archive member's name cell: its icon (a folder may have none) and its name, recycled.
//
//  Created by David Sherlock on 11/7/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import AppKitViews
import ThemedControls

/// One member of an archive in the archive tree: the file's icon by its name, a folder's (or none,
/// with folder icons off, the name then starting where a file's does), and the name. Built once and
/// reconfigured as the outline recycles it.
final class ArchiveEntryCellView: NSTableCellView {
    private static let iconLeading: CGFloat = 2
    private static let iconSize: CGFloat = 14
    private static let nameAfterIcon = iconLeading + iconSize + 6
    /// Where the icon is centred in the cell, which the outline puts on the chevron column for a file
    /// while folders have no icons (`RecyclingOutlineView.leafIconCentre`).
    static let iconCentre = iconLeading + iconSize / 2
    private static let nameWithoutIcon = nameAfterIcon - (iconCentre + RecyclingOutlineView.chevronCentreBeforeCell)

    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private var nameLeading: NSLayoutConstraint!
    /// The icon's symbol as last configured, for tests.
    private(set) var symbolForTesting: String?

    init() {
        super.init(frame: .zero)
        icon.imageScaling = .scaleProportionallyDown
        name.lineBreakMode = .byTruncatingMiddle
        addSubviewsForAutoLayout(icon, name)
        imageView = icon
        textField = name
        nameLeading = name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.nameAfterIcon)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.iconLeading),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: Self.iconSize),
            icon.heightAnchor.constraint(equalToConstant: Self.iconSize),
            nameLeading,
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
        ])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Shows one member: `symbol` nil leaves no icon and starts the name where the icon would be.
    func configure(symbol: String?, tint: NSColor, name text: String, font: NSFont) {
        symbolForTesting = symbol
        icon.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        icon.isHidden = symbol == nil
        icon.contentTintColor = tint
        nameLeading.constant = symbol == nil ? Self.nameWithoutIcon : Self.nameAfterIcon
        name.stringValue = text
        name.font = font
        name.textColor = Theme.sidebarText
    }
}
