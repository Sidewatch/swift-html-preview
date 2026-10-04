//
//  JSONTreeView+EditTarget.swift
//  Sidewatch
//
//  Which half of a row was edited.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit

extension JSONTreeView {
    /// Which half of a row was edited.
    public enum EditTarget { case key, value }
}
