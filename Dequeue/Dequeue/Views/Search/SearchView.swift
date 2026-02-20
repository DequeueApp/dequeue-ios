//
//  SearchView.swift
//  Dequeue
//
//  Unified search across tasks and stacks
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.dequeue", category: "SearchView")

struct SearchView: View {
    @Environment(\.searchService) private var searchService
    @State private var searchText = ""
    @State private var results: [SearchResultItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if !hasSearched {
                    emptySearchPrompt
                } else if isSearching {
                    searchingIndicator
                } else if results.isEmpty {
                    noResultsView
                } else {
                    resultsList
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search tasks and stacks...")
            .onChange(of: searchText) { _, newValue in
                performDebouncedSearch(query: newValue)
            }
            .onSubmit(of: .search) {
                performImmediateSearch()
            }
        }
    }

    // MARK: - Content Views

    private var emptySearchPrompt: some View {
        ContentUnavailableView {
            Label("Search Dequeue", systemImage: "magnifyingglass")
        } description: {
            Text("Find tasks and stacks by name, notes, or content.")
        }
    }

    private var searchingIndicator: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Searching...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        ContentUnavailableView.search(text: searchText)
    }

    private var resultsList: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            let taskResults = results.filter { $0.type == "task" }
            let stackResults = results.filter { $0.type == "stack" }

            if !taskResults.isEmpty {
                Section("Tasks (\(taskResults.count))") {
                    ForEach(taskResults) { result in
                        if let task = result.task {
                            TaskSearchRow(task: task)
                        }
                    }
                }
            }

            if !stackResults.isEmpty {
                Section("Stacks (\(stackResults.count))") {
                    ForEach(stackResults) { result in
                        if let stack = result.stack {
                            StackSearchRow(stack: stack)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Search Logic

    private func performDebouncedSearch(query: String) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            hasSearched = false
            errorMessage = nil
            return
        }

        // Debounce: wait 300ms after typing stops
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await executeSearch(query: trimmed)
        }
    }

    private func performImmediateSearch() {
        searchTask?.cancel()
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await executeSearch(query: trimmed)
        }
    }

    @MainActor
    private func executeSearch(query: String) async {
        guard let searchService else {
            errorMessage = "Search is not available."
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            let response = try await searchService.search(query: query)
            guard !Task.isCancelled else { return }
            results = response.results
            hasSearched = true
        } catch is CancellationError {
            // Ignore cancellation
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            hasSearched = true
        }

        isSearching = false
    }
}

// MARK: - Task Search Row

struct TaskSearchRow: View {
    let task: SearchTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                priorityIndicator
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.status == "completed")
                    .foregroundStyle(task.status == "completed" ? .secondary : .primary)
                Spacer()
                statusBadge
            }

            if let notes = task.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                if let dueDate = task.dueAtDate {
                    Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(dueDate < Date() ? .red : .secondary)
                }

                Spacer()

                Text(task.updatedAtDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var priorityIndicator: some View {
        switch task.priority {
        case 3:
            Image(systemName: "exclamationmark.3")
                .foregroundStyle(.red)
                .font(.caption)
        case 2:
            Image(systemName: "exclamationmark.2")
                .foregroundStyle(.orange)
                .font(.caption)
        case 1:
            Image(systemName: "exclamationmark")
                .foregroundStyle(.blue)
                .font(.caption)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch task.status {
        case "completed":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case "blocked":
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }
}

// MARK: - Stack Search Row

struct StackSearchRow: View {
    let stack: SearchStack

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stack.title)
                    .font(.body)
                Spacer()
                if stack.isActive {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
            }

            HStack {
                Label(
                    "\(stack.completedTaskCount)/\(stack.taskCount) tasks",
                    systemImage: "checklist"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if stack.taskCount > 0 {
                    ProgressView(value: stack.progress)
                        .frame(maxWidth: 60)
                }

                Spacer()

                Text(stack.updatedAtDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SearchView()
}
