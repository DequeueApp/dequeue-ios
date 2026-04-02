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
    @Environment(\.authService) private var authService
    @State private var searchText = ""
    @State private var results: [SearchResultItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?
    @State private var requiresReauth = false

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
            .searchable(text: $searchText, prompt: "Search tasks, stacks, and arcs...")
            .onChange(of: searchText) { _, newValue in
                performDebouncedSearch(query: newValue)
            }
            .onSubmit(of: .search) {
                performImmediateSearch()
            }
            .alert("Session Expired", isPresented: $requiresReauth) {
                Button("Sign In Again", role: .destructive) {
                    // Sign-out is handled by the auth state observer in the app root;
                    // clearing the Clerk session will redirect to the login screen.
                    Task { await signOut() }
                }
                Button("Cancel", role: .cancel) {
                    requiresReauth = false
                }
            } message: {
                Text("Your session has expired. Please sign in again to use search.")
            }
        }
    }

    // MARK: - Content Views

    private var emptySearchPrompt: some View {
        ContentUnavailableView {
            Label("Search Dequeue", systemImage: "magnifyingglass")
        } description: {
            Text("Find tasks, stacks, and arcs by name, notes, or content.")
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
            let arcResults = results.filter { $0.type == "arc" }

            if !arcResults.isEmpty {
                Section("Arcs (\(arcResults.count))") {
                    ForEach(arcResults) { result in
                        if let arc = result.arc {
                            ArcSearchRow(arc: arc)
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

            if !taskResults.isEmpty {
                Section("Tasks (\(taskResults.count))") {
                    ForEach(taskResults) { result in
                        if let task = result.task {
                            TaskSearchRow(task: task)
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
        defer { isSearching = false }

        do {
            let response = try await searchService.search(query: query)
            guard !Task.isCancelled else { return }
            results = response.results
            hasSearched = true
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch SearchError.notAuthenticated {
            // Session is genuinely broken — prompt the user to re-authenticate.
            // Do not show a generic error; show the re-auth alert instead.
            logger.warning("Search requires re-authentication — showing re-auth alert")
            requiresReauth = true
            hasSearched = false
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            hasSearched = true
        }
    }

    // MARK: - Sign Out

    private func signOut() async {
        do {
            try await authService.signOut()
        } catch {
            logger.error("Sign-out after search 401 failed: \(error.localizedDescription)")
        }
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

// MARK: - Arc Search Row

struct ArcSearchRow: View {
    let arc: SearchArc

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                arcIcon
                Text(arc.title)
                    .font(.body)
                    .strikethrough(arc.isCompleted)
                    .foregroundStyle(arc.isCompleted ? .secondary : .primary)
                Spacer()
                if arc.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            HStack {
                Label(
                    "\(arc.completedStackCount)/\(arc.stackCount) stacks",
                    systemImage: "square.stack"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if arc.stackCount > 0 {
                    ProgressView(value: arc.progress)
                        .frame(maxWidth: 60)
                }

                Spacer()

                if let dueDate = arc.dueAtDate {
                    Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(dueDate < Date() && !arc.isCompleted ? .red : .secondary)
                } else {
                    Text(arc.updatedAtDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var arcIcon: some View {
        if let colorHex = arc.colorHex, let color = Color(hex: colorHex) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        } else {
            Image(systemName: "archivebox")
                .foregroundStyle(.purple)
                .font(.caption)
        }
    }
}

#Preview {
    SearchView()
}
