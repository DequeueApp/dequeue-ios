//
//  StringExtensions.swift
//  Dequeue
//
//  Utilities for string manipulation
//

import Foundation

extension String {
    /// Converts empty string to nil, otherwise returns the string
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    /// Returns the string, or a default value if empty
    func orIfEmpty(_ default: String) -> String {
        isEmpty ? `default` : self
    }
}

/// Default title used for drafts when user leaves title empty
let defaultDraftTitle = "Untitled"
