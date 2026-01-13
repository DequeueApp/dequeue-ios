//
//  TagInputView.swift
//  Dequeue
//
//  Tag input component with autocomplete suggestions
//

import SwiftUI
import Combine

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

    /// Debounce publisher for search
    @State private var searchSubject = PassthroughSubject<String, Never>()
    @State private var debouncedText = ""
    @State private var cancellables = Set<AnyCancellable>()

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Selected tags row
            if !selectedTags.isEmpty {
                selectedTagsRow
            }

            // Input field with suggestions
            inputFieldSection
        }
        .onAppear {
            setupDebounce()
        }
    }

    // MARK: - Selected Tags Row

    private var selectedTagsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(selectedTags, id: \.id) { tag in
                    TagChip(tag: tag, showRemoveButton: true) {
                        removeTag(tag)
                    }
                }
            }
        }
    }

    // MARK: - Input Field

    private var inputFieldSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Add tag...", text: $inputText)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .onChange(of: inputText) { _, newValue in
                        searchSubject.send(newValue)
                        showSuggestions = !newValue.isEmpty
                    }
                    .onSubmit {
                        handleSubmit()
                    }
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
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Suggestions list
            if showSuggestions && (showCreateNewOption || !filteredSuggestions.isEmpty) {
                suggestionsView
            }
        }
    }

    // MARK: - Suggestions View

    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Existing tag suggestions
            ForEach(filteredSuggestions, id: \.id) { tag in
                suggestionRow(for: tag)
            }

            // Create new option
            if showCreateNewOption {
                createNewRow
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

    private func suggestionRow(for tag: Tag) -> some View {
        Button {
            selectTag(tag)
        } label: {
            HStack {
                if let colorHex = tag.colorHex, let color = Color(hex: colorHex) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var createNewRow: some View {
        Button {
            createNewTag()
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.blue)

                Text("Create \"\(inputText.trimmingCharacters(in: .whitespaces))\"")
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func setupDebounce() {
        searchSubject
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { text in
                debouncedText = text
            }
            .store(in: &cancellables)
    }

    private func selectTag(_ tag: Tag) {
        selectedTags.append(tag)
        onTagAdded(tag)
        clearInput()
    }

    private func removeTag(_ tag: Tag) {
        selectedTags.removeAll { $0.id == tag.id }
        onTagRemoved(tag)
    }

    private func createNewTag() {
        let trimmedName = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if let newTag = onNewTagCreated(trimmedName) {
            selectedTags.append(newTag)
            onTagAdded(newTag)
        }
        clearInput()
    }

    private func handleSubmit() {
        // If exact match in suggestions, select it
        if let exactMatch = filteredSuggestions.first(where: {
            $0.normalizedName == debouncedText.lowercased().trimmingCharacters(in: .whitespaces)
        }) {
            selectTag(exactMatch)
        } else if showCreateNewOption {
            createNewTag()
        }
    }

    private func clearInput() {
        inputText = ""
        debouncedText = ""
        showSuggestions = false
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
