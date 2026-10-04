//
//  DatabaseView+Mode.swift
//  Sidewatch
//
//  Which view of the database is showing: results, structure or diagram.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import UniformTypeIdentifiers
import FoundationExtensions

extension DatabaseView {
    /// Which view of the database is showing. Switched from the breadcrumb's surface button, the
    /// one place the app puts mode switches — never a segment bar inside the surface.
    public enum Mode: Int { case results, structure, diagram }
}
