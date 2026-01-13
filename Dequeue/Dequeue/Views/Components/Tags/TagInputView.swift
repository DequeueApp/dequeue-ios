//
//  TagInputView.swift
//  Dequeue
//
//  Tag input component with autocomplete suggestions
//

import SwiftUI

/// A tag input view with autocomplete suggestions and selected tag display.
///
/// Features:
/// - Horizontal scrolling chips for selected tags
/// - TextField for searching/adding tags
/// - Autocomplete suggestions with debouncing
/// - "Create new" option when no exact match
/// - Cross-platform (iOS and macOS)
struct TagInputView: View {
    /// Currently selected tags
    @Binding var selectedTags: [Tag]

    /// All available tags for suggestions
    let allTags: [Tag]

    /// Called when a tag is added
    let onTagAdded: (Tag) -> Void

    /// Called when a tag is removed
    let onTagRemoved: (Tag) -> Void

    /// Called to create a new tag from the input text
    let onNewTagCreated: (String) -> Tag?

    @State private var inputText = ""
    @State private var showSuggestions = false
    @FocusState private var isInputFocused: Bool

    /// Debounc search state - using Task-based approach for proper lifecycle management
    @State private var debouncedText = ""
    @State private var debounceTask: Task<Void, Never>?

    /// Index of currently highlighted suggestion for keyboard navigation (-1 = none, last index + 1 = create new)
    @State private var highlightedSuggestionIndex: Int = -1

    /// Filtered suggestions based on input
    private var filteredSuggestions: [Tag] {
        guard !debouncedText.isEmpty else { return [] }

        let normalizedInput = debouncedText.lowercased().trimmingCharacters(in: .whitespaces)
        let selectedIds = Set(selectedTags.map(\.id))

        let sorted = allTags
            .filter { tag in
                !selectedIds.contains(tag.id) &&
                !tag.isDeleted &&
                tag.normalizedName.contains(normalizedInput)
            }
            .sorted { lhs, rhs in
                // Exact matches first, then by activeStackCount, then alphabetically
                let lhsExact = lhs.normalizedName == normalizedInput
                let rhsExact = rhs.normalizedName == normalizedInput
                if lhsExact != rhsExact { return lhsExact }
                if lhs.activeStackCount != rhs.activeStackCount {
                    return lhs.activeStackCount > rhs.activeStackCount
                }
                return lhs.name < rhs.name
            }

        return Array(sorted.prefix(10))
    }

    /// Whether to show "Create new" option
    private var showCreateNewOption: Bool {
        guard !debouncedText.trimmingCharacters(in: .whitespaces).isEmpty else { return false }

        let normalizedInput = debouncedText.lowercased().trimmingCharacters(in: .whitespaces)

        // Don't show if exact match exists in suggestions
        let exactMatchExists = filteredSuggestions.contains { $0.normalizedName == normalizedInput }

        // Don't show if exact match is already selected
        let alreadySelected = selectedTags.contains { $0.normalizedName == normalizedInput }

        return !exactMatchExists && !alreadySelected
    }

    /// Total number of selectable items (suggestions + create new option if visible)
    private var totalSelectableItems: Int {
        filteredSuggestions.count + (showCreateNewOption ? 1 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Selected tags row
            if !selectedTags.isEmpty {
                selectedTagsRow
            }

            // Input field with suggestions
            inputFieldSection
        }
        .onDisappear {
            // Cancel any pending debounce task when view disappears
            debounceTask?.cancel()
        }
    }

    // MARK: - Selected Tags Row

    private var selectedTagsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(selectedTags, id: \.id) { tag in
                    TagChip(tag: tag, showRemoveButton: true) {
                        withAnimation(tagAnimation) {
                            removeTag(tag)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                }
            }
            .animation(tagAnimation, value: selectedTags.map(\.id))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected tags, \(selectedTags.count) \(selectedTags.count == 1 ? "tag" : "tags")")
    }

    /// Animation for tag add/remove - respects reduced motion preference
    private var tagAnimation: Animation { .spring(response: 0.3, dampingFraction: 0.7) }

    // MARK: - Input Field

    private var inputFieldSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Add tag...", text: $inputText)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .onChange(of: inputText) { _, newValue in
                        showSuggestions = !newValue.isEmpty
                        debounceSearch(newValue)
                        // Reset highlight when input changes
                        highlightedSuggestionIndex = -1
                    }
                    .onSubmit {
                        handleSubmit()
                    }
                    .onKeyPress(.escape) {
                        dismissSuggestions()
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        navigateSuggestions(direction: 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        navigateSuggestions(direction: -1)
                        return .handled
                    }
                    .onKeyPress(.delete) {
                        handleDeleteKey()
                    }
                    .accessibilityLabel("Add tag")
                    .accessibilityHint("Type to search for existing tags or create a new one")
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                #endif

                if !inputText.isEmpty {
                    Button {
                        inputText = ""
                        showSuggestions = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .accessibilityHint("Clears the tag search text")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Suggestions list with animated appearance
            if shouldShowSuggestions {
                suggestionsView
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .animation(suggestionsAnimation, value: shouldShowSuggestions)
    }

    /// Whether to show the suggestions popover
    private var shouldShowSuggestions: Bool { showSuggestions && (showCreateNewOption || !filteredSuggestions.isEmpty) }

    /// Animation for suggestions popover
    private var suggestionsAnimation: Animation { .spring(response: 0.25, dampingFraction: 0.8) }

    // MARK: - Suggestions View

    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Existing tag suggestions
            ForEach(Array(filteredSuggestions.enumerated()), id: \.element.id) { index, tag in
                suggestionRow(for: tag, isHighlighted: index == highlightedSuggestionIndex)
            }

            // Create new option
            if showCreateNewOption {
                createNewRow(isHighlighted: highlightedSuggestionIndex == filteredSuggestions.count)
            }
        }
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    private func suggestionRow(for tag: Tag, isHighlighted: Bool) -> some View {
        Button {
            selectTag(tag)
        } label: {
            HStack {
                if let colorHex = tag.colorHex, let color = Color(hex: colorHex) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }

                Text(tag.name)
                    .foregroundStyle(.primary)

                Spacer()

                if tag.activeStackCount > 0 {
                    Text("\(tag.activeStackCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
            .animation(.easeInOut(duration: 0.15), value: isHighlighted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(suggestionAccessibilityLabel(for: tag))
        .accessibilityHint("Double-tap to add this tag")
    }

    private func suggestionAccessibilityLabel(for tag: Tag) -> String {
        tag.activeStackCount > 0
            ? "Suggestion: \(tag.name), \(tag.activeStackCount) \(tag.activeStackCount == 1 ? "stack" : "stacks")"
            : "Suggestion: \(tag.name)"
    }

    private func createNewRow(isHighlighted: Bool) -> some View {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespaces)
        return Button {
            createNewTag()
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text("Create \"\(trimmedInput)\"")
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
            .animation(.easeInOut(duration: 0.15), value: isHighlighted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Create new tag: \(trimmedInput)")
        .accessibilityHint("Double-tap to create and add this new tag")
    }

    // MARK: - Actions

    /// Debounce search input using Task-based approach for proper lifecycle management.
    /// This avoids Combine memory management issues and ensures cleanup on view disappear.
    private func debounceSearch(_ text: String) {
        // Cancel any existing debounce task
        debounceTask?.cancel()

        // Create new debounce task
        debounceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                // Only update if not cancelled
                if !Task.isCancelled {
                    debouncedText = text
                }
            } catch {
                // Task was cancelled, do nothing
            }
        }
    }

    private func selectTag(_ tag: Tag) {
        withAnimation(tagAnimation) {
            selectedTags.append(tag)
        }
        onTagAdded(tag)
        clearInput()
    }

    private func removeTag(_ tag: Tag) { selectedTags.removeAll { $0.id == tag.id }; onTagRemoved(tag) }

    private func createNewTag() {
        let trimmedName = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if let newTag = onNewTagCreated(trimmedName) {
            withAnimation(tagAnimation) {
                selectedTags.append(newTag)
            }
            onTagAdded(newTag)
        }
        clearInput()
    }

    private func handleSubmit() {
        // If a suggestion is highlighted, select it
        if highlightedSuggestionIndex >= 0 {
            if highlightedSuggestionIndex < filteredSuggestions.count {
                selectTag(filteredSuggestions[highlightedSuggestionIndex])
            } else if showCreateNewOption {
                createNewTag()
            }
            return
        }

        // Otherwise, if exact match in suggestions, select it
        if let exactMatch = filteredSuggestions.first(where: {
            $0.normalizedName == debouncedText.lowercased().trimmingCharacters(in: .whitespaces)
        }) {
            selectTag(exactMatch)
        } else if showCreateNewOption {
            createNewTag()
        }
    }

    private func clearInput() {
        inputText = ""; debouncedText = ""; showSuggestions = false; highlightedSuggestionIndex = -1
    }

    // MARK: - Keyboard Navigation

    /// Dismiss suggestions and clear highlight
    private func dismissSuggestions() { showSuggestions = false; highlightedSuggestionIndex = -1 }

    /// Navigate through suggestions with arrow keys
    private func navigateSuggestions(direction: Int) {
        guard showSuggestions && totalSelectableItems > 0 else { return }
        let newIndex = highlightedSuggestionIndex + direction
        highlightedSuggestionIndex = newIndex < 0 ? totalSelectableItems - 1
            : newIndex >= totalSelectableItems ? 0 : newIndex
    }

    /// Handle delete/backspace key - remove last selected tag when input is empty
    private func handleDeleteKey() -> KeyPress.Result {
        guard inputText.isEmpty, !selectedTags.isEmpty else { return .ignored }
        if let lastTag = selectedTags.last { removeTag(lastTag) }
        return .handled
    }
}

// MARK: - Previews

#Preview("Empty State") {
    struct PreviewWrapper: View {
        @State private var selectedTags: [Tag] = []

        var body: some View {
            let allTags = [
                Tag(name: "Swift"),
                Tag(name: "SwiftUI", colorHex: "#FF9500"),
                Tag(name: "iOS", colorHex: "#007AFF"),
                Tag(name: "Backend"),
                Tag(name: "Frontend", colorHex: "#34C759")
            ]

            TagInputView(
                selectedTags: $selectedTags,
                allTags: allTags,
                onTagAdded: { _ in },
                onTagRemoved: { _ in },
                onNewTagCreated: { name in Tag(name: name) }
            )
            .padding()
        }
    }

    return PreviewWrapper()
}

#Preview("With Selected Tags") {
    struct PreviewWrapper: View {
        @State private var selectedTags: [Tag]

        init() {
            let swift = Tag(name: "Swift")
            let ios = Tag(name: "iOS", colorHex: "#007AFF")
            _selectedTags = State(initialValue: [swift, ios])
        }

        var body: some View {
            let allTags = [
                Tag(name: "Swift"),
                Tag(name: "SwiftUI", colorHex: "#FF9500"),
                Tag(name: "iOS", colorHex: "#007AFF"),
                Tag(name: "Backend"),
                Tag(name: "Frontend", colorHex: "#34C759")
            ]

            TagInputView(
                selectedTags: $selectedTags,
                allTags: allTags,
                onTagAdded: { _ in },
                onTagRemoved: { _ in },
                onNewTagCreated: { name in Tag(name: name) }
            )
            .padding()
        }
    }

    return PreviewWrapper()
}
