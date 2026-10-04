//
//  JSONItem+Kind.swift
//  Sidewatch
//
//  A JSON value's kind, which picks its colour from the live theme.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit

extension JSONItem {
    /// Semantic value class — the display color is looked up live from `Theme` so a
    /// theme flip recolors without rebuilding the tree (rebuilding is exactly what
    /// collapses the user's expanded nodes).
    public enum Kind { case container, null, bool, number, string, other }
}
