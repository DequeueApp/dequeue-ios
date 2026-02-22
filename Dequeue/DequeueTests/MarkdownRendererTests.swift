//
//  MarkdownRendererTests.swift
//  DequeueTests
//
//  Tests for MarkdownRenderer — text rendering and formatting.
//

import Testing
import Foundation
import SwiftUI

@testable import Dequeue

// MARK: - MarkdownRenderer Tests

@Suite("MarkdownRenderer")
@MainActor
struct MarkdownRendererTests {
    @Test("Renders plain text without crash")
    @MainActor func plainText() {
        let result = MarkdownRenderer.render("Hello world")
        #expect(String(result.characters) == "Hello world")
    }

    @Test("Renders bold text")
    @MainActor func boldText() {
        let result = MarkdownRenderer.render("**bold**")
        #expect(String(result.characters) == "bold")
    }

    @Test("Renders italic text")
    @MainActor func italicText() {
        let result = MarkdownRenderer.render("_italic_")
        #expect(String(result.characters) == "italic")
    }

    @Test("Renders inline code")
    @MainActor func inlineCode() {
        let result = MarkdownRenderer.render("`code`")
        #expect(String(result.characters) == "code")
    }

    @Test("Renders strikethrough")
    @MainActor func strikethrough() {
        let result = MarkdownRenderer.render("~~strike~~")
        #expect(String(result.characters) == "strike")
    }

    @Test("Renders mixed formatting")
    @MainActor func mixedFormatting() {
        let result = MarkdownRenderer.render("**bold** and _italic_ text")
        #expect(String(result.characters) == "bold and italic text")
    }

    @Test("Renders links")
    @MainActor func links() {
        let result = MarkdownRenderer.render("[click here](https://example.com)")
        #expect(String(result.characters) == "click here")
    }

    @Test("Handles empty string")
    @MainActor func emptyString() {
        let result = MarkdownRenderer.render("")
        #expect(String(result.characters) == "")
    }

    @Test("Handles invalid markdown gracefully")
    @MainActor func invalidMarkdown() {
        let result = MarkdownRenderer.render("** unmatched bold")
        #expect(!String(result.characters).isEmpty)
    }

    @Test("Full render handles headers")
    @MainActor func fullRenderHeaders() {
        let result = MarkdownRenderer.renderFull("# Hello")
        #expect(String(result.characters).contains("Hello"))
    }

    @Test("Full render handles lists")
    @MainActor func fullRenderLists() {
        let result = MarkdownRenderer.renderFull("- item 1\n- item 2")
        let text = String(result.characters)
        #expect(text.contains("item 1"))
        #expect(text.contains("item 2"))
    }

    @Test("Preserves line breaks in inline mode")
    @MainActor func preservesLineBreaks() {
        let result = MarkdownRenderer.render("line 1\nline 2")
        let text = String(result.characters)
        #expect(text.contains("line 1"))
        #expect(text.contains("line 2"))
    }
}

// MARK: - Markdown Cheat Sheet Tests

@Suite("MarkdownCheatSheet")
@MainActor
struct MarkdownCheatSheetTests {
    @Test("Has all expected examples")
    func hasExamples() {
        let sheet = MarkdownCheatSheet()
        #expect(sheet.examples.count == 10)
    }

    @Test("All examples have syntax and description")
    func examplesHaveContent() {
        let sheet = MarkdownCheatSheet()
        for example in sheet.examples {
            #expect(!example.syntax.isEmpty)
            #expect(!example.description.isEmpty)
        }
    }
}
