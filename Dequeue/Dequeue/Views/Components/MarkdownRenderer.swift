//
//  MarkdownRenderer.swift
//  Dequeue
//
//  Renders Markdown text as an AttributedString for display in SwiftUI.
//  Supports: bold, italic, code, links, headers, lists, and strikethrough.
//

import SwiftUI
import Foundation
import os

private let logger = Logger(subsystem: "com.dequeue", category: "MarkdownRenderer")

// MARK: - Markdown Renderer

/// Converts markdown text to AttributedString with custom styling
@MainActor
struct MarkdownRenderer {

    /// Renders markdown string to AttributedString
    /// Falls back to plain text on parse failure
    static func render(_ markdown: String, baseFont: Font = .body, baseColor: Color = .primary) -> AttributedString {
        do {
            var result = try AttributedString(markdown: markdown, options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            ))

            // Apply base styling
            result.font = baseFont
            result.foregroundColor = baseColor

            return result
        } catch {
            logger.debug("Markdown parse failed, returning plain text: \(error.localizedDescription)")
            var plain = AttributedString(markdown)
            plain.font = baseFont
            plain.foregroundColor = baseColor
            return plain
        }
    }

    /// Renders full markdown including block elements (headers, lists, etc.)
    static func renderFull(_ markdown: String) -> AttributedString {
        do {
            var result = try AttributedString(markdown: markdown, options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            ))
            return result
        } catch {
            return AttributedString(markdown)
        }
    }
}

// MARK: - Markdown Text View

/// SwiftUI view that renders markdown text
struct MarkdownText: View {
    let text: String
    var baseFont: Font
    var baseColor: Color

    init(_ text: String, font: Font = .body, color: Color = .primary) {
        self.text = text
        self.baseFont = font
        self.baseColor = color
    }

    var body: some View {
        Text(MarkdownRenderer.render(text, baseFont: baseFont, baseColor: baseColor))
    }
}

// MARK: - Markdown Note Editor

/// A markdown-aware text editor with toolbar formatting buttons
struct MarkdownNoteEditor: View {
    @Binding var text: String
    @State private var showPreview = false
    @FocusState private var isFocused: Bool

    var placeholder: String = "Add notes..."
    var minHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            formattingToolbar

            Divider()

            if showPreview {
                // Preview mode
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if text.isEmpty {
                            Text("Nothing to preview")
                                .foregroundStyle(.secondary)
                                .italic()
                        } else {
                            Text(MarkdownRenderer.renderFull(text))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .frame(minHeight: minHeight)
            } else {
                // Edit mode
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $text)
                        .focused($isFocused)
                        .scrollContentBackground(.hidden)
                        .font(.body.monospaced())
                        .frame(minHeight: minHeight)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                FormatButton(icon: "bold", tooltip: "Bold") {
                    wrapSelection(with: "**")
                }
                FormatButton(icon: "italic", tooltip: "Italic") {
                    wrapSelection(with: "_")
                }
                FormatButton(icon: "strikethrough", tooltip: "Strikethrough") {
                    wrapSelection(with: "~~")
                }
                FormatButton(icon: "chevron.left.forwardslash.chevron.right", tooltip: "Code") {
                    wrapSelection(with: "`")
                }

                Divider()
                    .frame(height: 20)

                FormatButton(icon: "list.bullet", tooltip: "List") {
                    insertPrefix("- ")
                }
                FormatButton(icon: "list.number", tooltip: "Numbered List") {
                    insertPrefix("1. ")
                }
                FormatButton(icon: "checkmark.square", tooltip: "Checkbox") {
                    insertPrefix("- [ ] ")
                }

                Divider()
                    .frame(height: 20)

                FormatButton(icon: "link", tooltip: "Link") {
                    insertText("[link text](url)")
                }
                FormatButton(icon: "text.quote", tooltip: "Quote") {
                    insertPrefix("> ")
                }

                Spacer()

                // Preview toggle
                Button {
                    showPreview.toggle()
                } label: {
                    Image(systemName: showPreview ? "pencil" : "eye")
                        .font(.subheadline)
                        .foregroundStyle(showPreview ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func wrapSelection(with wrapper: String) {
        text += "\(wrapper)text\(wrapper)"
    }

    private func insertPrefix(_ prefix: String) {
        if text.isEmpty || text.hasSuffix("\n") {
            text += prefix
        } else {
            text += "\n\(prefix)"
        }
    }

    private func insertText(_ newText: String) {
        text += newText
    }
}

// MARK: - Format Button

private struct FormatButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(tooltip)
    }
}

// MARK: - Markdown Cheat Sheet

struct MarkdownCheatSheet: View {
    let examples: [(syntax: String, description: String)] = [
        ("**bold**", "Bold text"),
        ("_italic_", "Italic text"),
        ("~~strikethrough~~", "Strikethrough"),
        ("`code`", "Inline code"),
        ("- item", "Bullet list"),
        ("1. item", "Numbered list"),
        ("- [ ] task", "Checkbox"),
        ("[text](url)", "Link"),
        ("> quote", "Block quote"),
        ("# Heading", "Header"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Markdown Reference")
                .font(.headline)

            ForEach(examples, id: \.syntax) { example in
                HStack(spacing: 12) {
                    Text(example.syntax)
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                        .frame(width: 120, alignment: .leading)
                    Text(example.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview("Markdown Editor") {
    @Previewable @State var text = "# Task Notes\n\nThis is **bold** and _italic_ text.\n\n- [ ] First item\n- [x] Done item\n- [ ] Third item\n\n> Important note here"

    MarkdownNoteEditor(text: $text)
        .padding()
}

#Preview("Markdown Text") {
    VStack(alignment: .leading, spacing: 8) {
        MarkdownText("**Bold text** and _italic text_")
        MarkdownText("Visit [Dequeue](https://dequeue.app) for more")
        MarkdownText("`inline code` in text")
        MarkdownText("~~strikethrough~~ text")
    }
    .padding()
}
